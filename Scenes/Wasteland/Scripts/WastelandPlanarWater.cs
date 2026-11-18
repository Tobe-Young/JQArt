using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[ExecuteAlways]
public class WastelandPlanarWater : MonoBehaviour {
 public float waterHeight=-.1f;
 public int reflectionWidth=1024;
 Camera reflectionCamera;RenderTexture reflectionTexture;static bool busy;
 void OnEnable(){RenderPipelineManager.beginCameraRendering+=Render;}
 void OnDisable(){RenderPipelineManager.beginCameraRendering-=Render;Release();}
 void Release(){if(reflectionCamera)DestroyImmediate(reflectionCamera.gameObject);if(reflectionTexture){reflectionTexture.Release();DestroyImmediate(reflectionTexture);}Shader.SetGlobalFloat("_PlanarValid",0);}
 void Render(ScriptableRenderContext context,Camera source){
  if(busy||!source||source.cameraType==CameraType.Reflection||source.cameraType==CameraType.Preview||source==reflectionCamera)return;
  if(source.transform.position.y<waterHeight+.05f)return;
  if(!reflectionCamera){var go=new GameObject("Water reflection temporary camera"){hideFlags=HideFlags.HideAndDontSave};reflectionCamera=go.AddComponent<Camera>();reflectionCamera.enabled=false;}
  int height=Mathf.Max(128,Mathf.RoundToInt(reflectionWidth/source.aspect));
  if(!reflectionTexture||reflectionTexture.width!=reflectionWidth||reflectionTexture.height!=height){if(reflectionTexture){reflectionTexture.Release();DestroyImmediate(reflectionTexture);}reflectionTexture=new RenderTexture(reflectionWidth,height,24,RenderTextureFormat.ARGBHalf){name="Canal planar reflection",hideFlags=HideFlags.HideAndDontSave};reflectionTexture.Create();}
  reflectionCamera.CopyFrom(source);reflectionCamera.enabled=false;reflectionCamera.cameraType=CameraType.Reflection;reflectionCamera.cullingMask=source.cullingMask&~(1<<4);reflectionCamera.targetTexture=reflectionTexture;reflectionCamera.allowMSAA=false;
  var add=reflectionCamera.GetUniversalAdditionalCameraData();add.renderPostProcessing=false;add.renderShadows=true;add.requiresColorOption=CameraOverrideOption.Off;add.requiresDepthOption=CameraOverrideOption.Off;
  Matrix4x4 mirror=Matrix4x4.identity;mirror.m11=-1;mirror.m13=2*waterHeight;
  reflectionCamera.worldToCameraMatrix=source.worldToCameraMatrix*mirror;reflectionCamera.transform.position=mirror.MultiplyPoint(source.transform.position);
  Vector3 pos=reflectionCamera.worldToCameraMatrix.MultiplyPoint(new Vector3(0,waterHeight+.035f,0));Vector3 normal=reflectionCamera.worldToCameraMatrix.MultiplyVector(Vector3.up).normalized;
  reflectionCamera.projectionMatrix=source.CalculateObliqueMatrix(new Vector4(normal.x,normal.y,normal.z,-Vector3.Dot(pos,normal)));
  bool oldCulling=GL.invertCulling;
  try{busy=true;GL.invertCulling=!oldCulling;
#pragma warning disable 0618
   UniversalRenderPipeline.RenderSingleCamera(context,reflectionCamera);
#pragma warning restore 0618
   Shader.SetGlobalTexture("_PlanarReflection",reflectionTexture);Shader.SetGlobalMatrix("_PlanarVP",GL.GetGPUProjectionMatrix(reflectionCamera.projectionMatrix,true)*reflectionCamera.worldToCameraMatrix);Shader.SetGlobalFloat("_PlanarValid",1);
  }finally{GL.invertCulling=oldCulling;busy=false;}
 }
}
