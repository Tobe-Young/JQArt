Shader "Codex Water/Flowing Water URP"
{
    Properties
    {
        _ShallowColor("Shallow water", Color) = (0.13,0.61,0.57,1)
        _DeepColor("Deep water", Color) = (0.018,0.15,0.19,1)
        _FoamColor("Foam", Color) = (0.83,0.97,0.94,1)
        [Normal] _NormalMap("Water normals",2D)="bump"{}
        _NoiseMap("Foam noise",2D)="gray"{}
        _FlowSpeed("Downstream speed (m/s)",Range(0,5))=1.2
        _EdgeFlow("Outward edge flow (m/s)",Range(0,2))=.38
        _NormalStrength("Ripple strength",Range(0,2))=.55
        _NormalScale("Ripple tiling per meter",Range(.02,2))=.32
        _Refraction("Refraction",Range(0,.04))=.009
        _DepthTint("Absorption",Range(.01,2))=.24
        _WaterDepth("Minimum color depth (m)",Range(0,6))=1.15
        _FoamWidth("Lip foam width (m)",Range(.02,2))=.38
        _Smoothness("Smoothness",Range(0,1))=.94
        _WaveHeight("Ripple displacement (m)",Range(0,.15))=.035
        _UseSceneTextures("Depth / refraction enabled",Float)=1
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "WaterSurface"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            // The surface recomposites refraction with alpha=1; writing depth prevents
            // the far waterfall from drawing through the top of the river.
            ZWrite On
            Cull Off
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "WaterCommon.hlsl"
            TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);
            CBUFFER_START(UnityPerMaterial)
                half4 _ShallowColor,_DeepColor,_FoamColor;
                float _FlowSpeed,_EdgeFlow,_NormalStrength,_NormalScale,_Refraction,_DepthTint,_WaterDepth,_FoamWidth,_Smoothness,_WaveHeight,_UseSceneTextures;
            CBUFFER_END
            struct A {float4 positionOS:POSITION;float3 normalOS:NORMAL;float4 tangentOS:TANGENT;float2 uv:TEXCOORD0;float4 edge:TEXCOORD1;};
            struct V {float4 positionCS:SV_POSITION;float3 positionWS:TEXCOORD0;half3 normalWS:TEXCOORD1;half4 tangentWS:TEXCOORD2;float2 uv:TEXCOORD3;float2 edge:TEXCOORD4;half fog:TEXCOORD5;};
            V Vert(A i)
            {
                V o;
                // Only generated river meshes carry this explicit edge-distance signature.
                // Ordinary/lightmap UVs must never be interpreted as bank distances.
                bool riverData=abs(i.edge.z-27182)<.25 && abs(i.edge.w-31415)<.25;
                if(!riverData)
                {
                    float n2=dot(i.normalOS,i.normalOS);
                    float3 normalOS=n2>1e-8?i.normalOS*rsqrt(n2):float3(0,1,0);
                    float3 tangentOS=i.tangentOS.xyz-normalOS*dot(normalOS,i.tangentOS.xyz);
                    if(dot(tangentOS,tangentOS)<1e-8)
                    {
                        float3 axis=abs(normalOS.x)<.9?float3(1,0,0):float3(0,0,1);
                        tangentOS=axis-normalOS*dot(normalOS,axis);
                    }
                    i.normalOS=normalOS;
                    i.tangentOS=float4(normalize(tangentOS),abs(i.tangentOS.w)>.5?i.tangentOS.w:1);
                    VertexNormalInputs basis=GetVertexNormalInputs(i.normalOS,i.tangentOS);
                    float3 relativeWS=TransformObjectToWorld(i.positionOS.xyz)-TransformObjectToWorld(float3(0,0,0));
                    // Planar mapping in physical meters: no UV2, UV0 scale or tangent requirement.
                    i.uv=float2(dot(relativeWS,normalize(basis.tangentWS)),dot(relativeWS,normalize(basis.bitangentWS)));
                    i.edge.xy=float2(10000,10000);
                }
                float fade=smoothstep(0,.65,i.edge.x)*smoothstep(0,.65,i.edge.y);
                float wave=sin(i.uv.x*.85+i.uv.y*1.4-_Time.y*1.7)*.65+sin(i.uv.x*1.7-i.uv.y*.8-_Time.y*2.3)*.35;
                i.positionOS.xyz+=i.normalOS*wave*_WaveHeight*fade;
                VertexPositionInputs p=GetVertexPositionInputs(i.positionOS.xyz);
                VertexNormalInputs n=GetVertexNormalInputs(i.normalOS,i.tangentOS);
                o.positionCS=p.positionCS;o.positionWS=p.positionWS;o.normalWS=n.normalWS;
                o.tangentWS=half4(n.tangentWS,i.tangentOS.w*GetOddNegativeScale());o.uv=i.uv;o.edge=i.edge.xy;o.fog=ComputeFogFactor(p.positionCS.z);return o;
            }
            half4 Frag(V i):SV_Target
            {
                float edge=min(i.edge.x,i.edge.y);
                float side=(i.edge.x-i.edge.y)/max(i.edge.x+i.edge.y,.001);
                float2 flow=float2(_FlowSpeed,side*_EdgeFlow*(.3+.7*pow(abs(side),2)));
                float2 q=(i.uv-_Time.y*flow)*_NormalScale;
                half3 a=UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap,sampler_NormalMap,q),_NormalStrength);
                half3 b=UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap,sampler_NormalMap,q*1.73+float2(-_Time.y*.055,_Time.y*.03)),_NormalStrength*.55);
                half3 nt=normalize(half3(a.xy+b.xy,a.z*b.z));
                half3 n0=normalize(i.normalWS),t=normalize(i.tangentWS.xyz),bt=normalize(cross(n0,t))*i.tangentWS.w;
                half3 n=normalize(nt.x*t+nt.y*bt+nt.z*n0);
                half3 view=SafeNormalize(GetWorldSpaceViewDir(i.positionWS));
                float2 screenUV=GetNormalizedScreenSpaceUV(i.positionCS);
                float depth=30;
                half3 behind=_ShallowColor.rgb;
                if(_UseSceneTextures>.5)
                {
                    float scene=WaterEyeDepth(SampleSceneDepth(screenUV));
                    float own=-TransformWorldToView(i.positionWS).z;
                    depth=max(0,scene-own);
                    float2 offset=nt.xy*_Refraction*saturate(depth*.7);
                    float2 refrUV=saturate(screenUV+offset);
                    float refrDepth=WaterEyeDepth(SampleSceneDepth(refrUV));
                    if(refrDepth<own+.02)refrUV=screenUV;
                    behind=SampleSceneColor(refrUV);
                }
                float absorb=1-exp(-max(depth,_WaterDepth)*_DepthTint);
                half3 water=lerp(_ShallowColor.rgb,_DeepColor.rgb,saturate(absorb));
                half3 col=lerp(behind,water,lerp(.32,.94,absorb));
                float f=.025+.975*pow(1-saturate(dot(n,view)),5);
                half3 reflectColor=GlossyEnvironmentReflection(reflect(-view,n),i.positionWS,1-_Smoothness,1);
                col=lerp(col,reflectColor,min(.8,f));
                Light light=GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half3 halfDir=SafeNormalize(view+light.direction);
                float glint=pow(saturate(dot(n,halfDir)),lerp(64,650,_Smoothness));
                col+=light.color*glint*.85*light.shadowAttenuation;
                float noise=SAMPLE_TEXTURE2D(_NoiseMap,sampler_NoiseMap,i.uv*float2(.45,.9)-_Time.y*flow*.32).r;
                float lip=(1-smoothstep(_FoamWidth*.1,_FoamWidth*(.6+noise),edge));
                float contact=(1-smoothstep(.04,.34,depth))*smoothstep(.32,.66,noise);
                float streak=pow(saturate(noise-.35),3)*.22;
                float foam=saturate(lip*.82+contact*.7+streak);
                half3 foamLight=_FoamColor.rgb*(.62+.38*saturate(light.direction.y))*lerp(.7,1,light.shadowAttenuation);
                col=lerp(col,foamLight,foam);
                return half4(MixFog(col,i.fog),1);
            }
            ENDHLSL
        }
    }
}
