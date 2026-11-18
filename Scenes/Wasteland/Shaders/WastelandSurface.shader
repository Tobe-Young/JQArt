Shader "Wasteland/URP Weathered Surface" {
Properties {
 _BaseMap("Albedo",2D)="white"{} _BaseColor("Tint",Color)=(1,1,1,1)
 _NeutralAlbedo("Remove source hue before tint",Range(0,1))=0
 _BumpMap("Normal",2D)="bump"{} _BumpScale("Normal strength",Float)=0.5
 _MetallicGlossMap("Metal / smoothness",2D)="black"{} _Metallic("Metal",Range(0,1))=0
 _Smoothness("Smoothness",Range(0,1))=0.2 _Cutoff("Alpha clip",Range(0,1))=0.35
 _RustTex("Fine oxidation",2D)="white"{} _RustMask("Macro weathering",2D)="gray"{}
 _RustAmount("Oxidation",Range(0,1))=0 _Variation("Surface variation",Range(0,1))=0.2 _Stochastic("Fine irregularity",Float)=0
 _Foliage("Foliage",Float)=0 _Atlas("Atlas rows",Float)=1 _Wind("Wind",Float)=0 _Water("Water",Float)=0
 [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull",Float)=2
}
SubShader {
Tags {"RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry"}
HLSLINCLUDE
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
TEXTURE2D(_BaseMap);SAMPLER(sampler_BaseMap);TEXTURE2D(_BumpMap);SAMPLER(sampler_BumpMap);
TEXTURE2D(_MetallicGlossMap);SAMPLER(sampler_MetallicGlossMap);TEXTURE2D(_RustTex);SAMPLER(sampler_RustTex);TEXTURE2D(_RustMask);SAMPLER(sampler_RustMask);
CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST,_BaseColor;float _BumpScale,_Metallic,_Smoothness,_Cutoff,_RustAmount,_Variation,_Foliage,_Atlas,_Wind,_Cull,_Stochastic,_Water,_NeutralAlbedo;
CBUFFER_END
TEXTURE2D(_PlanarReflection);SAMPLER(sampler_PlanarReflection);float4x4 _PlanarVP;float _PlanarValid;
struct Attributes {float4 positionOS:POSITION;float3 normalOS:NORMAL;float4 tangentOS:TANGENT;float2 uv:TEXCOORD0;};
struct Varyings {float4 positionCS:SV_POSITION;float2 uv:TEXCOORD0;float3 positionWS:TEXCOORD1;half3 normalWS:TEXCOORD2;half4 tangentWS:TEXCOORD3;half fog:TEXCOORD4;};
float3 Displaced(Attributes i){float3 p=TransformObjectToWorld(i.positionOS.xyz);float w=frac(i.uv.y*_Atlas+.0001);w=smoothstep(.05,.95,w);p.xz+=float2(1,.43)*(sin(p.x*.45+p.z*.38+_Time.y*1.4)+.35*sin(p.z*2.1+_Time.y*2.4))*w*w*_Wind;return p;}
Varyings vert(Attributes i){Varyings o;o.positionWS=Displaced(i);o.positionCS=TransformWorldToHClip(o.positionWS);o.uv=TRANSFORM_TEX(i.uv,_BaseMap);o.normalWS=TransformObjectToWorldNormal(i.normalOS);o.tangentWS=half4(TransformObjectToWorldDir(i.tangentOS.xyz),i.tangentOS.w*GetOddNegativeScale());o.fog=ComputeFogFactor(o.positionCS.z);return o;}
half4 frag(Varyings i,FRONT_FACE_TYPE face:FRONT_FACE_SEMANTIC):SV_Target {
 half4 a=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,i.uv);
 half neutral=dot(a.rgb,half3(.2126,.7152,.0722));a.rgb=lerp(a.rgb,half3(neutral,neutral,neutral),_NeutralAlbedo);a*=_BaseColor;
 if(_Foliage>.5)clip(a.a-_Cutoff);
 half3 n=normalize(i.normalWS);n*=IS_FRONT_VFACE(face,1,-1);half3 t=normalize(i.tangentWS.xyz);half3 b=cross(n,t)*i.tangentWS.w;
 half3 nt=UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap,sampler_BumpMap,i.uv),_BumpScale);n=normalize(t*nt.x+b*nt.y+n*nt.z);if(_Foliage>.5)n=normalize(lerp(n,half3(0,1,0),.60));
 if(_Water>.5){float2 w=i.positionWS.xz;float tm=_Time.y;float rx=cos(w.x*2.8+w.y*.8+tm*.7)*.045+cos(w.x*8.1-w.y*3.1+tm*1.2)*.026;float rz=sin(w.y*3.3+w.x*.6+tm*.52)*.040+sin(w.y*9.2-w.x*1.9+tm*1.7)*.021;n=normalize(float3(rx,1,rz));a.rgb=_BaseColor.rgb;}
 half rough=SAMPLE_TEXTURE2D(_MetallicGlossMap,sampler_MetallicGlossMap,i.uv).a;
 half macro=SAMPLE_TEXTURE2D(_RustMask,sampler_RustMask,float2(i.positionWS.x*.017+i.positionWS.z*.023,i.positionWS.y*.023+i.positionWS.z*.011)).r;
 half m2=SAMPLE_TEXTURE2D(_RustMask,sampler_RustMask,i.positionWS.xz*.031+float2(.31,.72)).r;
 half rust=saturate((macro*.72+m2*.28-.24)*2.5)*_RustAmount;
 if(_Foliage<.5){
  half3 fine=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,i.uv*1.813+float2(.317,.711)).rgb*_BaseColor.rgb;
  a.rgb=lerp(a.rgb,fine,.25*_Variation*_Stochastic);a.rgb*=lerp(1,lerp(.54,1.08,macro),_Variation);
  half3 r=SAMPLE_TEXTURE2D(_RustTex,sampler_RustTex,i.uv*.77).rgb*half3(.48,.33,.25)+half3(.09,.025,.006);a.rgb=lerp(a.rgb,r,rust);
 }
 SurfaceData s=(SurfaceData)0;s.albedo=a.rgb;s.metallic=lerp(_Metallic,.025,rust);s.smoothness=lerp(saturate(_Smoothness+rough*.14),.12,rust);s.normalTS=nt;s.occlusion=1;s.alpha=1;s.emission=(_Foliage>.5)?a.rgb*.025:0;
 InputData d=(InputData)0;d.positionWS=i.positionWS;d.normalWS=n;d.viewDirectionWS=GetWorldSpaceNormalizeViewDir(i.positionWS);d.shadowCoord=TransformWorldToShadowCoord(i.positionWS);d.bakedGI=lerp(half3(.16,.15,.13),half3(.38,.41,.43),saturate(n.y*.5+.5));d.normalizedScreenSpaceUV=GetNormalizedScreenSpaceUV(i.positionCS);d.shadowMask=half4(1,1,1,1);
 half4 col=UniversalFragmentPBR(d,s);
 if(_Water>.5&&_PlanarValid>.5){float4 rp=mul(_PlanarVP,float4(i.positionWS,1));float2 ruv=rp.xy/rp.w*.5+.5;ruv.y=1-ruv.y;ruv+=n.xz*.012;half3 refc=SAMPLE_TEXTURE2D(_PlanarReflection,sampler_PlanarReflection,saturate(ruv)).rgb;float fresnel=.12+.70*pow(1-saturate(dot(n,d.viewDirectionWS)),3);col.rgb=lerp(col.rgb,refc*half3(.80,.89,.86),fresnel);}
 col.rgb=MixFog(col.rgb,i.fog);return col;
}
float3 _LightDirection;float3 _LightPosition;
Varyings shadowVert(Attributes i){Varyings o=(Varyings)0;float3 p=Displaced(i);float3 n=TransformObjectToWorldNormal(i.normalOS);float3 l=_LightDirection;
#if _CASTING_PUNCTUAL_LIGHT_SHADOW
l=normalize(_LightPosition-p);
#endif
o.positionCS=TransformWorldToHClip(ApplyShadowBias(p,n,l));
#if UNITY_REVERSED_Z
o.positionCS.z=min(o.positionCS.z,UNITY_NEAR_CLIP_VALUE);
#else
o.positionCS.z=max(o.positionCS.z,UNITY_NEAR_CLIP_VALUE);
#endif
o.uv=TRANSFORM_TEX(i.uv,_BaseMap);return o;}
half4 shadowFrag(Varyings i):SV_Target {if(_Foliage>.5)clip(SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,i.uv).a-_Cutoff);return 0;}
ENDHLSL
Pass {Name "ForwardLit" Tags{"LightMode"="UniversalForward"} Cull [_Cull]
HLSLPROGRAM
#pragma target 3.5
#pragma vertex vert
#pragma fragment frag
#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
#pragma multi_compile _ _ADDITIONAL_LIGHTS
#pragma multi_compile_fragment _ _SHADOWS_SOFT
#pragma multi_compile_fog
ENDHLSL
}
Pass {Name "ShadowCaster" Tags{"LightMode"="ShadowCaster"} ZWrite On ZTest LEqual ColorMask 0 Cull [_Cull]
HLSLPROGRAM
#pragma target 3.5
#pragma vertex shadowVert
#pragma fragment shadowFrag
#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
ENDHLSL
}
Pass {Name "DepthOnly" Tags{"LightMode"="DepthOnly"} ZWrite On ColorMask R Cull [_Cull]
HLSLPROGRAM
#pragma target 3.5
#pragma vertex vert
#pragma fragment shadowFrag
ENDHLSL
}
}
}
