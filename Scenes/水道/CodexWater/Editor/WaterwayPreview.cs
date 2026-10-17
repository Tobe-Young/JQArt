#if UNITY_EDITOR
using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace CodexWater.Editor
{
    public static class WaterwayPreview
    {
        [MenuItem("Tools/Waterway/Render Quality Check")]
        public static void RenderCheck()
        {
            var fx=UnityEngine.Object.FindObjectOfType<WaterwayEffect>();if(!fx)throw new InvalidOperationException("Create the waterway effect first.");
            string folder=WaterwayBuilder.Root+"/Previews";Directory.CreateDirectory(folder);
            var cameraObject=new GameObject("Waterway QA Camera"){hideFlags=HideFlags.HideAndDontSave};var camera=cameraObject.AddComponent<Camera>();camera.enabled=false;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.028f,.044f,.055f);camera.nearClipPlane=.1f;camera.farClipPlane=1500;camera.fieldOfView=38;camera.allowHDR=true;
            var extra=cameraObject.AddComponent<UniversalAdditionalCameraData>();extra.requiresColorTexture=true;extra.requiresDepthTexture=true;extra.renderPostProcessing=false;extra.antialiasing=AntialiasingMode.FastApproximateAntialiasing;
            bool async=ShaderUtil.allowAsyncCompilation;ShaderUtil.allowAsyncCompilation=false;
            try
            {
                var renderers=fx.GetComponentsInChildren<MeshRenderer>();Bounds bounds=renderers[0].bounds;foreach(var r in renderers)bounds.Encapsulate(r.bounds);
                Vector3 center=bounds.center;float size=Mathf.Max(bounds.size.x,bounds.size.z);
                camera.orthographic=true;camera.transform.position=center+new Vector3(.2f,.8f,-1)*size;camera.transform.LookAt(center);
                float ex=0,ey=0;for(int x=-1;x<=1;x+=2)for(int y=-1;y<=1;y+=2)for(int z=-1;z<=1;z+=2){var q=camera.transform.InverseTransformPoint(center+Vector3.Scale(bounds.extents,new Vector3(x,y,z)));ex=Mathf.Max(ex,Mathf.Abs(q.x));ey=Mathf.Max(ey,Mathf.Abs(q.y));}camera.orthographicSize=Mathf.Max(ey,ex/(1400f/900f))*1.07f;
                Save(camera,folder+"/waterway-overview.png");
                var mesh=fx.transform.Find("Generated Water Effects/Flowing Surface").GetComponent<MeshFilter>();var verts=mesh.sharedMesh.vertices;
                int mid=(verts.Length/9/2)*9;Vector3 rim=mesh.transform.TransformPoint(verts[mid]);Vector3 other=mesh.transform.TransformPoint(verts[mid+8]);Vector3 outward=(rim-other).normalized;
                Vector3 tangent=(mesh.transform.TransformPoint(verts[mid+9])-rim).normalized;float scale=fx.transform.lossyScale.x;
                camera.orthographic=false;camera.fieldOfView=45;Vector3 focus=rim-Vector3.up*fx.waterfallHeight*scale*.35f;camera.transform.position=focus+(outward*20+Vector3.up*17+tangent*18)*scale;camera.transform.LookAt(focus);
                Save(camera,folder+"/waterway-detail.png");
                var messages=new System.Collections.Generic.List<string>();
                foreach(var shader in new[]{fx.surfaceMaterial.shader,fx.waterfallMaterial.shader,fx.mistMaterial.shader})foreach(var message in ShaderUtil.GetShaderMessages(shader))messages.Add(shader.name+": "+message.severity+" "+message.message);
                File.WriteAllText("Temp/CodexWaterShaderCheck.txt",messages.Count==0?"PASS: no shader compiler messages after rendering overview and detail.":string.Join("\n",messages));
            }
            finally{ShaderUtil.allowAsyncCompilation=async;UnityEngine.Object.DestroyImmediate(cameraObject);}
        }
        static void Save(Camera camera,string path)
        {
            var rt=RenderTexture.GetTemporary(1400,900,24,RenderTextureFormat.ARGB32,RenderTextureReadWrite.sRGB);var previous=RenderTexture.active;
            try{camera.targetTexture=rt;RenderPipeline.SubmitRenderRequest(camera,new UniversalRenderPipeline.SingleCameraRequest{destination=rt});RenderTexture.active=rt;var image=new Texture2D(rt.width,rt.height,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,rt.width,rt.height),0,0);image.Apply();File.WriteAllBytes(path,image.EncodeToPNG());UnityEngine.Object.DestroyImmediate(image);}
            finally{camera.targetTexture=null;RenderTexture.active=previous;RenderTexture.ReleaseTemporary(rt);}
        }
    }
}
#endif
