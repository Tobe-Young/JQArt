Shader "Wasteland/Shougang Fence Cutout" {
Properties { _BaseMap("Fence", 2D) = "white" {} }
SubShader {
Tags { "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" "RenderType"="TransparentCutout" }
Cull Off ZWrite On
HLSLINCLUDE
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
struct Vertex { float4 pos:POSITION; float2 uv:TEXCOORD0; };
struct Vary { float4 pos:SV_POSITION; float2 uv:TEXCOORD0; float3 world:TEXCOORD1; };
Vary vert(Vertex i) { Vary o; o.world=TransformObjectToWorld(i.pos.xyz); o.pos=TransformWorldToHClip(o.world); o.uv=i.uv; return o; }
half4 cutout(float2 uv) {
 float gap=step(17.0,uv.x)*(1.0-step(20.0,uv.x));
 float2 st=float2(uv.x,(1.0-gap)*0.5+(3.0+250.0*saturate(uv.y))/512.0);
 half4 c=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,st);
 if(uv.x>37.992 && min(abs(uv.y-.32),abs(uv.y-.8))>.009) c.a=0;
 clip(c.a-.33); return c;
}
half4 lit(Vary i):SV_Target { half4 c=cutout(i.uv); Light l=GetMainLight(TransformWorldToShadowCoord(i.world)); half3 n=half3(0,0,1);
 return half4(c.rgb*(max(half3(.24,.24,.24),SampleSH(n))+l.color*(.35+.65*abs(dot(n,l.direction)))*l.shadowAttenuation),1); }
half4 depth(Vary i):SV_Target { cutout(i.uv); return 0; }
ENDHLSL
Pass { Name "Forward" Tags { "LightMode"="UniversalForward" }
HLSLPROGRAM
#pragma vertex vert
#pragma fragment lit
#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
ENDHLSL
}
Pass { Name "DepthOnly" Tags { "LightMode"="DepthOnly" } ColorMask 0
HLSLPROGRAM
#pragma vertex vert
#pragma fragment depth
ENDHLSL
}
Pass { Name "ShadowCaster" Tags { "LightMode"="ShadowCaster" } ColorMask 0
HLSLPROGRAM
#pragma vertex vert
#pragma fragment depth
ENDHLSL
}
}
}
