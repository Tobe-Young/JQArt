#if UNITY_EDITOR
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;

namespace CodexWater.Editor
{
    public static class WaterwayBuilder
    {
        public const string Root="Assets/CodexWater";
        const string Generated=Root+"/Generated";
        const string KnownModel="Assets/Arts/Scenes/水道/Model/瀑布.fbx";
        const string KnownScene="Assets/Arts/Scenes/水道/Scence/水道.unity";
        const int Steps=300;
        struct RailPoint { public float u; public Vector3 p; public RailPoint(float u,Vector3 p){this.u=u;this.p=p;} }

        [MenuItem("Tools/Waterway/Create Water and Both Waterfalls")]
        public static void Create()
        {
            if(EditorApplication.isPlayingOrWillChangePlaymode)throw new InvalidOperationException("Exit Play Mode before building water.");
            var scene=SceneManager.GetActiveScene();
            MeshFilter source=null;
            if(Selection.activeGameObject)source=Selection.activeGameObject.GetComponentInChildren<MeshFilter>();
            if(!source || AssetDatabase.GetAssetPath(source.sharedMesh).StartsWith(Root))
                source=scene.GetRootGameObjects().SelectMany(g=>g.GetComponentsInChildren<MeshFilter>(true)).FirstOrDefault(m=>AssetDatabase.GetAssetPath(m.sharedMesh)==KnownModel);
            if(!source)throw new InvalidOperationException("Select the waterway model in the Hierarchy first.");
            Directory.CreateDirectory(Generated);Directory.CreateDirectory(Root+"/Backups");
            AssetDatabase.Refresh();
            string backup=Root+"/Backups/WaterwayBefore-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+".unity";
            if(!EditorSceneManager.SaveScene(scene,backup,true))throw new IOException("Could not save the scene backup.");
            var existing=scene.GetRootGameObjects().SelectMany(g=>g.GetComponentsInChildren<WaterwayEffect>(true)).FirstOrDefault(e=>e.source==source);
            var fx=existing;
            if(!fx)
            {
                var go=new GameObject("Waterway - Water and Waterfalls");Undo.RegisterCreatedObjectUndo(go,"Create waterway effect");
                SceneManager.MoveGameObjectToScene(go,scene);fx=Undo.AddComponent<WaterwayEffect>(go);fx.source=source;
                fx.originalRenderer=source.GetComponent<Renderer>();fx.originalRendererEnabled=fx.originalRenderer&&fx.originalRenderer.enabled;
            }
            PrepareMaterials(fx);Rebuild(fx);
            if(fx.originalRenderer){Undo.RecordObject(fx.originalRenderer,"Hide original waterway renderer");fx.originalRenderer.enabled=false;}
            EnableCameraTextures(scene);
            Selection.activeGameObject=fx.gameObject;
            if(SceneView.lastActiveSceneView){SceneView.lastActiveSceneView.sceneViewState.alwaysRefresh=true;SceneView.lastActiveSceneView.FrameSelected();}
            EditorSceneManager.MarkSceneDirty(scene);EditorSceneManager.SaveScene(scene);AssetDatabase.SaveAssets();
            WriteReport(fx,backup);
        }

        public static void Rebuild(WaterwayEffect fx)
        {
            if(!fx.source||!fx.source.sharedMesh)throw new InvalidOperationException("A source MeshFilter is required.");
            GetRails(fx.source,out var left,out var right,out float span);
            // Work in physical meters, while retaining the source's corrected scene scale.
            float factor=300f/Mathf.Max(span,.001f);Vector3 origin=fx.source.transform.position;
            for(int i=0;i<left.Length;i++){left[i]=(left[i]-origin)*factor;right[i]=(right[i]-origin)*factor;}
            Undo.RecordObject(fx,"Rebuild waterway");Undo.RecordObject(fx.transform,"Position waterway");
            fx.sourceSpan=span;fx.transform.SetPositionAndRotation(origin,Quaternion.identity);fx.transform.localScale=Vector3.one*(fx.restore300MeterSpan?1:span/300f);
            var old=fx.transform.Find("Generated Water Effects");if(old)Undo.DestroyObjectImmediate(old.gameObject);
            var root=new GameObject("Generated Water Effects");Undo.RegisterCreatedObjectUndo(root,"Rebuild waterway");root.transform.SetParent(fx.transform,false);
            var dist=new float[left.Length];for(int i=1;i<dist.Length;i++)dist[i]=dist[i-1]+Vector3.Distance((left[i]+right[i])*.5f,(left[i-1]+right[i-1])*.5f);
            fx.centerlineLength=dist[dist.Length-1];
            var surface=BuildSurface(left,right,dist);
            AddMesh(root.transform,"Flowing Surface",surface,fx.surfaceMaterial,"Surface");
            if(fx.leftWaterfall)BuildFall(root.transform,fx,left,right,true,"Left");
            if(fx.rightWaterfall)BuildFall(root.transform,fx,right,left,false,"Right");
            if(fx.originalRenderer)fx.originalRenderer.enabled=false;
            EditorUtility.SetDirty(fx);EditorSceneManager.MarkSceneDirty(fx.gameObject.scene);AssetDatabase.SaveAssets();
        }

        static void GetRails(MeshFilter source,out Vector3[] left,out Vector3[] right,out float span)
        {
            Mesh mesh=source.sharedMesh;var v=mesh.vertices;var uv=mesh.uv;var tris=mesh.triangles;
            if(uv.Length!=v.Length)throw new InvalidOperationException("The waterway needs its straight rectangular UV map.");
            var world=v.Select(p=>source.transform.TransformPoint(p)).ToArray();
            float top=world.Max(p=>p.y);float size=Mathf.Max(.001f,world.Max(p=>p.x)-world.Min(p=>p.x));
            var indices=new HashSet<int>();
            for(int k=0;k<tris.Length;k+=3)
            {
                int a=tris[k],b=tris[k+1],c=tris[k+2];
                if(top-world[a].y>size*.0001f||top-world[b].y>size*.0001f||top-world[c].y>size*.0001f)continue;
                Vector3 normal=Vector3.Cross(world[b]-world[a],world[c]-world[a]).normalized;
                if(Mathf.Abs(normal.y)<.95f)continue;indices.Add(a);indices.Add(b);indices.Add(c);
            }
            if(indices.Count<4)throw new InvalidOperationException("No horizontal top surface found. Keep the source waterway horizontal.");
            float minV=indices.Min(i=>uv[i].y),maxV=indices.Max(i=>uv[i].y),band=(maxV-minV)*.1f;
            if(band<.000001f)throw new InvalidOperationException("The top UV has no width.");
            var lo=indices.Where(i=>uv[i].y<minV+band).Select(i=>new RailPoint(uv[i].x,world[i])).OrderBy(p=>p.u).ToList();
            var hi=indices.Where(i=>uv[i].y>maxV-band).Select(i=>new RailPoint(uv[i].x,world[i])).OrderBy(p=>p.u).ToList();
            lo=Distinct(lo);hi=Distinct(hi);
            if(lo.Count<3||hi.Count<3)throw new InvalidOperationException("Cannot identify both long UV edges.");
            float minU=Mathf.Max(lo[0].u,hi[0].u),maxU=Mathf.Min(lo[lo.Count-1].u,hi[hi.Count-1].u);
            left=new Vector3[Steps+1];right=new Vector3[Steps+1];
            for(int i=0;i<=Steps;i++){float u=Mathf.Lerp(minU,maxU,i/(float)Steps);left[i]=Sample(lo,u);right[i]=Sample(hi,u);}
            span=Vector3.Distance((left[0]+right[0])*.5f,(left[Steps]+right[Steps])*.5f);
            if(span<.01f)throw new InvalidOperationException("Invalid waterway span.");
        }
        static List<RailPoint> Distinct(List<RailPoint> list){var r=new List<RailPoint>();foreach(var p in list)if(r.Count==0||Mathf.Abs(p.u-r[r.Count-1].u)>.000001f)r.Add(p);return r;}
        static Vector3 Sample(List<RailPoint> rail,float u){int i=0;while(i<rail.Count-2&&rail[i+1].u<u)i++;return Vector3.Lerp(rail[i].p,rail[i+1].p,Mathf.InverseLerp(rail[i].u,rail[i+1].u,u));}

        static Mesh BuildSurface(Vector3[] left,Vector3[] right,float[] dist)
        {
            // Eight lanes across the surface support subtle waves and a smooth outward-flow gradient.
            const int lanes=8;var v=new List<Vector3>();var uv=new List<Vector2>();var edge=new List<Vector2>();var tr=new List<int>();
            for(int i=0;i<left.Length;i++)for(int j=0;j<=lanes;j++)
            {float t=j/(float)lanes,w=Vector3.Distance(left[i],right[i]);v.Add(Vector3.Lerp(left[i],right[i],t)+Vector3.up*.025f);uv.Add(new Vector2(dist[i],t*w));edge.Add(new Vector2(t*w,(1-t)*w));}
            for(int i=0;i<left.Length-1;i++)for(int j=0;j<lanes;j++){int a=i*(lanes+1)+j;Quad(tr,a,a+1,a+lanes+2,a+lanes+1);}
            if(Vector3.Cross(v[tr[1]]-v[tr[0]],v[tr[2]]-v[tr[0]]).y<0)Flip(tr);
            var mesh=MakeMesh("Waterway Surface",v,uv,edge,tr);
            mesh.SetUVs(1,edge.Select(e=>new Vector4(e.x,e.y,27182,31415)).ToList());
            return mesh;
        }
        static void BuildFall(Transform root,WaterwayEffect fx,Vector3[] rim,Vector3[] other,bool left,string label)
        {
            const int rows=24;var v=new List<Vector3>();var uv=new List<Vector2>();var stages=new List<Vector2>();var tr=new List<int>();
            var baseLine=new Vector3[rim.Length];var crest=new Vector3[rim.Length];float dist=0;
            for(int i=0;i<rim.Length;i++)
            {
                if(i>0)dist+=Vector3.Distance(rim[i],rim[i-1]);var outward=(rim[i]-other[i]).normalized;
                crest[i]=rim[i]+Vector3.up*.035f;
                for(int j=0;j<=rows;j++)
                {
                    float t=j/(float)rows;
                    float push=fx.outwardSpread*(Mathf.Sqrt(t+.025f)-Mathf.Sqrt(.025f));
                    Vector3 p=crest[i]+outward*push-Vector3.up*(fx.waterfallHeight*t);
                    v.Add(p);uv.Add(new Vector2(dist,t*fx.waterfallHeight));stages.Add(new Vector2(i/(float)(rim.Length-1),t));
                    if(j==rows)baseLine[i]=p+Vector3.up*.08f;
                }
            }
            for(int i=0;i<rim.Length-1;i++)for(int j=0;j<rows;j++){int a=i*(rows+1)+j;Quad(tr,a,a+1,a+rows+2,a+rows+1);}
            Vector3 normal=Vector3.Cross(v[tr[1]]-v[tr[0]],v[tr[2]]-v[tr[0]]);if(Vector3.Dot(normal,rim[0]-other[0])<0)Flip(tr);
            AddMesh(root,label+" Water Curtain",MakeMesh(label+" Fall",v,uv,stages,tr),fx.waterfallMaterial,label+"Fall");
            if(!fx.particles)return;
            Mesh bottomEmitter=Emitter(baseLine,rim,.45f,label+"BottomEmitter");
            Mesh topEmitter=Emitter(crest,other,.12f,label+"CrestEmitter");
            MakeParticles(root,label+" Impact Mist",bottomEmitter,fx.mistMaterial,dist,fx.particleDensity,0);
            MakeParticles(root,label+" Splash Droplets",bottomEmitter,fx.sprayMaterial,dist,fx.particleDensity,1);
            MakeParticles(root,label+" Crest Spray",topEmitter,fx.sprayMaterial,dist,fx.particleDensity,2);
        }
        static Mesh Emitter(Vector3[] line,Vector3[] other,float width,string key)
        {
            var v=new List<Vector3>();var uv=new List<Vector2>();var e=new List<Vector2>();var tr=new List<int>();
            for(int i=0;i<line.Length;i++){Vector3 across=line[i]-other[i];across.y=0;across=across.normalized*width;v.Add(line[i]-across);v.Add(line[i]+across);uv.Add(Vector2.zero);uv.Add(Vector2.one);e.Add(Vector2.zero);e.Add(Vector2.zero);}
            for(int i=0;i<line.Length-1;i++)Quad(tr,i*2,i*2+1,i*2+3,i*2+2);
            if(Vector3.Cross(v[tr[1]]-v[tr[0]],v[tr[2]]-v[tr[0]]).y<0)Flip(tr);
            return SaveMesh(MakeMesh(key,v,uv,e,tr),key);
        }
        static void MakeParticles(Transform root,string name,Mesh emitter,Material mat,float length,float density,int type)
        {
            var go=new GameObject(name);go.transform.SetParent(root,false);var ps=go.AddComponent<ParticleSystem>();ps.Stop(true,ParticleSystemStopBehavior.StopEmittingAndClear);
            var main=ps.main;main.duration=6;main.loop=true;main.prewarm=true;main.playOnAwake=true;main.simulationSpace=ParticleSystemSimulationSpace.Local;main.scalingMode=ParticleSystemScalingMode.Hierarchy;
            main.maxParticles=type==0?1600:1200;main.startLifetime=type==0?new ParticleSystem.MinMaxCurve(1.8f,3.1f):new ParticleSystem.MinMaxCurve(.45f,1.05f);
            main.startSpeed=type==0?new ParticleSystem.MinMaxCurve(.3f,.85f):new ParticleSystem.MinMaxCurve(1.1f,2.6f);
            main.startSize=type==0?new ParticleSystem.MinMaxCurve(.9f,1.9f):new ParticleSystem.MinMaxCurve(.035f,.10f);
            main.startColor=type==0?new Color(.9f,1,1,.24f):new Color(.9f,1,1,.65f);
            main.gravityModifier=type==0?0:.32f;main.startRotation=new ParticleSystem.MinMaxCurve(0,Mathf.PI*2);
            var em=ps.emission;em.rateOverTime=length*density*(type==0?.6f:type==1?1f:.25f);
            var shape=ps.shape;shape.enabled=true;shape.shapeType=ParticleSystemShapeType.Mesh;shape.mesh=emitter;shape.meshShapeType=ParticleSystemMeshShapeType.Triangle;shape.randomDirectionAmount=type==0?.32f:.7f;shape.normalOffset=.015f;
            var color=ps.colorOverLifetime;color.enabled=true;var gradient=new Gradient();gradient.SetKeys(new[]{new GradientColorKey(Color.white,0),new GradientColorKey(Color.white,1)},new[]{new GradientAlphaKey(0,0),new GradientAlphaKey(1,.15f),new GradientAlphaKey(.6f,.55f),new GradientAlphaKey(0,1)});color.color=gradient;
            var size=ps.sizeOverLifetime;size.enabled=true;size.size=new ParticleSystem.MinMaxCurve(1,AnimationCurve.Linear(0,type==0?.6f:1,1,type==0?2.2f:.3f));
            var noise=ps.noise;noise.enabled=true;noise.strength=type==0?.45f:.17f;noise.frequency=.24f;noise.scrollSpeed=.25f;noise.octaveCount=2;noise.quality=ParticleSystemNoiseQuality.Medium;
            var renderer=ps.GetComponent<ParticleSystemRenderer>();renderer.sharedMaterial=mat;renderer.renderMode=type==0?ParticleSystemRenderMode.Billboard:ParticleSystemRenderMode.Stretch;renderer.lengthScale=type==0?1:2;renderer.velocityScale=type==0?0:.06f;renderer.maxParticleSize=.12f;renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;
            ps.useAutoRandomSeed=false;ps.randomSeed=(uint)(type*91+(name.StartsWith("Left")?103:719));ps.Simulate(3,true,true);ps.Play();
        }
        static void Quad(List<int> t,int a,int b,int c,int d){t.AddRange(new[]{a,b,c,a,c,d});}
        static void Flip(List<int> t){for(int i=0;i<t.Count;i+=3){int a=t[i+1];t[i+1]=t[i+2];t[i+2]=a;}}
        static Mesh MakeMesh(string name,List<Vector3> v,List<Vector2> uv,List<Vector2> uv2,List<int> tri)
        {var m=new Mesh{name=name,indexFormat=IndexFormat.UInt32};m.SetVertices(v);m.SetUVs(0,uv);m.SetUVs(1,uv2);m.SetTriangles(tri,0);m.RecalculateNormals();m.RecalculateTangents();m.RecalculateBounds();var b=m.bounds;b.Expand(.8f);m.bounds=b;return m;}
        static Mesh SaveMesh(Mesh mesh,string key)
        {
            string p=Generated+"/"+key+".asset";var old=AssetDatabase.LoadAssetAtPath<Mesh>(p);
            if(old){EditorUtility.CopySerialized(mesh,old);UnityEngine.Object.DestroyImmediate(mesh);EditorUtility.SetDirty(old);return old;}
            AssetDatabase.CreateAsset(mesh,p);return mesh;
        }
        static void AddMesh(Transform parent,string name,Mesh mesh,Material mat,string key)
        {var go=new GameObject(name);go.transform.SetParent(parent,false);go.AddComponent<MeshFilter>().sharedMesh=SaveMesh(mesh,key);var r=go.AddComponent<MeshRenderer>();r.sharedMaterial=mat;r.shadowCastingMode=ShadowCastingMode.Off;r.receiveShadows=true;r.reflectionProbeUsage=ReflectionProbeUsage.BlendProbesAndSkybox;}

        public static void PrepareMaterials(WaterwayEffect fx)
        {
            Directory.CreateDirectory(Generated);AssetDatabase.Refresh();
            Texture2D noise=Texture("FlowNoise.png",false,0),normal=Texture("WaterNormal.png",true,1),mist=Texture("Mist.png",false,2),drop=Texture("Droplet.png",false,3);
            fx.surfaceMaterial=Material("WaterSurface","Codex Water/Flowing Water URP");fx.surfaceMaterial.SetTexture("_NormalMap",normal);fx.surfaceMaterial.SetTexture("_NoiseMap",noise);
            fx.waterfallMaterial=Material("Waterfall","Codex Water/Waterfall Curtain URP");fx.waterfallMaterial.SetTexture("_NormalMap",normal);fx.waterfallMaterial.SetTexture("_NoiseMap",noise);
            fx.mistMaterial=Material("Mist","Codex Water/Soft Spray URP");fx.mistMaterial.SetTexture("_BaseMap",mist);fx.mistMaterial.SetColor("_BaseColor",new Color(.83f,.94f,.97f,.58f));
            fx.sprayMaterial=Material("Droplets","Codex Water/Soft Spray URP");fx.sprayMaterial.SetTexture("_BaseMap",drop);fx.sprayMaterial.SetColor("_BaseColor",new Color(.88f,.97f,1,.8f));
            foreach(var m in new[]{fx.surfaceMaterial,fx.waterfallMaterial,fx.mistMaterial,fx.sprayMaterial})EditorUtility.SetDirty(m);
        }
        static Material Material(string key,string shader)
        {string p=Generated+"/"+key+".mat";var m=AssetDatabase.LoadAssetAtPath<Material>(p);if(m)return m;var s=Shader.Find(shader);if(!s)throw new InvalidOperationException("Shader not imported: "+shader);m=new Material(s){name=key};AssetDatabase.CreateAsset(m,p);return m;}
        static float TileNoise(float x,float y,float f,float seed)
        {float a=Mathf.PerlinNoise(x*f+seed,y*f+seed),b=Mathf.PerlinNoise((x-1)*f+seed,y*f+seed),c=Mathf.PerlinNoise(x*f+seed,(y-1)*f+seed),d=Mathf.PerlinNoise((x-1)*f+seed,(y-1)*f+seed);return Mathf.Lerp(Mathf.Lerp(a,b,x),Mathf.Lerp(c,d,x),y);}
        static float Height(float x,float y){x=Mathf.Repeat(x,1);y=Mathf.Repeat(y,1);return TileNoise(x,y,8,11)*.55f+TileNoise(x,y,19,23)*.3f+TileNoise(x,y,43,37)*.15f;}
        static Texture2D Texture(string file,bool normal,int type)
        {
            string p=Generated+"/"+file;var existing=AssetDatabase.LoadAssetAtPath<Texture2D>(p);if(existing)return existing;
            const int n=256;var texture=new Texture2D(n,n,TextureFormat.RGBA32,true,true);var pixels=new Color[n*n];
            for(int y=0;y<n;y++)for(int x=0;x<n;x++)
            {
                float u=x/(float)n,v=y/(float)n;
                if(type==0)pixels[y*n+x]=new Color(Height(u,v),TileNoise(u,v,24,43),TileNoise(u,v,12,67),1);
                else if(type==1){float e=1f/n;float dx=Height(u+e,v)-Height(u-e,v),dy=Height(u,v+e)-Height(u,v-e);Vector3 q=new Vector3(-dx*7,-dy*7,1).normalized;pixels[y*n+x]=new Color(q.x*.5f+.5f,q.y*.5f+.5f,q.z*.5f+.5f,1);}
                else {float r=new Vector2(u*2-1,v*2-1).magnitude;float a=Mathf.Pow(Mathf.Clamp01(1-r*r),type==2?2.5f:1.5f);if(type==2)a*=Mathf.SmoothStep(.1f,1,Mathf.PerlinNoise(u*7+12,v*7+31));pixels[y*n+x]=new Color(1,1,1,a);}
            }
            texture.SetPixels(pixels);texture.Apply();File.WriteAllBytes(p,texture.EncodeToPNG());UnityEngine.Object.DestroyImmediate(texture);AssetDatabase.ImportAsset(p,ImportAssetOptions.ForceSynchronousImport);
            var importer=(TextureImporter)AssetImporter.GetAtPath(p);importer.textureType=normal?TextureImporterType.NormalMap:TextureImporterType.Default;importer.sRGBTexture=false;importer.wrapMode=type<2?TextureWrapMode.Repeat:TextureWrapMode.Clamp;importer.mipmapEnabled=true;importer.alphaSource=TextureImporterAlphaSource.FromInput;importer.alphaIsTransparency=type>=2;importer.textureCompression=TextureImporterCompression.Uncompressed;importer.SaveAndReimport();return AssetDatabase.LoadAssetAtPath<Texture2D>(p);
        }
        static void EnableCameraTextures(Scene scene)
        {
            foreach(var camera in scene.GetRootGameObjects().SelectMany(g=>g.GetComponentsInChildren<Camera>(true)))
            {var data=camera.GetComponent<UniversalAdditionalCameraData>();if(!data)data=Undo.AddComponent<UniversalAdditionalCameraData>(camera.gameObject);Undo.RecordObject(data,"Enable water depth and refraction");data.requiresDepthTexture=true;data.requiresColorTexture=true;EditorUtility.SetDirty(data);}
            var pipeline=GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
            if(pipeline){Undo.RecordObject(pipeline,"Enable water depth and opaque textures");pipeline.supportsCameraDepthTexture=true;pipeline.supportsCameraOpaqueTexture=true;EditorUtility.SetDirty(pipeline);}
        }
        [Serializable] class Report{public string status,scene,backup;public float sourceSpan,length,height;public int renderers,particleSystems;public string[] shaderMessages;}
        static void WriteReport(WaterwayEffect fx,string backup)
        {
            var errors=new List<string>();foreach(var shader in new[]{fx.surfaceMaterial.shader,fx.waterfallMaterial.shader,fx.mistMaterial.shader})foreach(var msg in ShaderUtil.GetShaderMessages(shader))errors.Add(shader.name+": "+msg.severity+" "+msg.message);
            File.WriteAllText("Temp/CodexWaterReport.json",JsonUtility.ToJson(new Report{status="installed",scene=fx.gameObject.scene.path,backup=backup,sourceSpan=fx.sourceSpan,length=fx.centerlineLength,height=fx.waterfallHeight,renderers=fx.GetComponentsInChildren<MeshRenderer>().Length,particleSystems=fx.GetComponentsInChildren<ParticleSystem>().Length,shaderMessages=errors.ToArray()},true));
        }
        [MenuItem("Tools/Waterway/Restore Original Renderer")]
        static void Restore()
        {var fx=Selection.activeGameObject?Selection.activeGameObject.GetComponentInParent<WaterwayEffect>():null;if(!fx)return;if(fx.originalRenderer){Undo.RecordObject(fx.originalRenderer,"Restore source");fx.originalRenderer.enabled=fx.originalRendererEnabled;}Undo.RecordObject(fx.gameObject,"Disable water effects");fx.gameObject.SetActive(false);}
    }

    [CustomEditor(typeof(WaterwayEffect))]
    class WaterwayInspector:UnityEditor.Editor
    {
        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();var fx=(WaterwayEffect)target;
            EditorGUILayout.HelpBox("Change geometry settings, then Rebuild. Edit material properties for live flow, color and foam controls. The original model is retained.",MessageType.Info);
            EditorGUILayout.LabelField("Source span",fx.sourceSpan.ToString("F2")+" Unity units");EditorGUILayout.LabelField("Water centerline",fx.centerlineLength.ToString("F1")+" m");
            if(GUILayout.Button("Rebuild Waterfalls / 重建瀑布"))WaterwayBuilder.Rebuild(fx);
            if(GUILayout.Button("Preview Particles / 预览粒子")){fx.PlayParticles();SceneView.RepaintAll();}
            if(GUILayout.Button("Stop Particle Preview / 停止粒子预览"))fx.StopParticles();
        }
    }

    [InitializeOnLoad]
    static class WaterwayAutoInstall
    {
        static readonly double Start=EditorApplication.timeSinceStartup;
        static WaterwayAutoInstall(){EditorApplication.update+=Tick;}
        static void Tick()
        {
            const string request="Temp/CodexWaterInstall.request";
            const string preview="Temp/CodexWaterPreview.request";
            if(File.Exists(preview)&&!EditorApplication.isCompiling&&!EditorApplication.isUpdating&&!EditorApplication.isPlayingOrWillChangePlaymode&&EditorApplication.timeSinceStartup-Start>3){File.Delete(preview);try{WaterwayPreview.RenderCheck();}catch(Exception e){File.WriteAllText("Temp/CodexWaterShaderCheck.txt",e.ToString());}return;}
            if(!File.Exists(request)||EditorApplication.isCompiling||EditorApplication.isUpdating||EditorApplication.isPlayingOrWillChangePlaymode||EditorApplication.timeSinceStartup-Start<3)return;
            if(SceneManager.GetActiveScene().path!="Assets/Arts/Scenes/水道/Scence/水道.unity")return;
            File.Delete(request);
            try{var model=SceneManager.GetActiveScene().GetRootGameObjects().SelectMany(g=>g.GetComponentsInChildren<MeshFilter>(true)).FirstOrDefault(m=>AssetDatabase.GetAssetPath(m.sharedMesh)=="Assets/Arts/Scenes/水道/Model/瀑布.fbx");if(!model)throw new InvalidOperationException("Waterway model not found in active scene.");Selection.activeGameObject=model.gameObject;WaterwayBuilder.Create();EditorApplication.delayCall+=WaterwayPreview.RenderCheck;}catch(Exception e){File.WriteAllText("Temp/CodexWaterReport.json",e.ToString());Debug.LogException(e);}
        }
    }
}
#endif
