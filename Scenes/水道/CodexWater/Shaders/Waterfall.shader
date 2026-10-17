Shader "Codex Water/Waterfall Curtain URP"
{
    Properties
    {
        _WaterColor("Water tint",Color)=(.13,.47,.48,1)
        _FoamColor("Whitewater",Color)=(.85,.97,.96,1)
        _NoiseMap("Flow noise",2D)="gray"{}
        [Normal] _NormalMap("Ripple normals",2D)="bump"{}
        _FallSpeed("Fall speed",Range(.2,12))=4.5
        _Density("Curtain density",Range(.1,1))=.84
        _StreakScale("Streak scale",Range(.1,4))=1.2
        _Turbulence("Turbulence (m)",Range(0,.3))=.065
        _SoftDepth("Intersection fade (m)",Range(.01,2))=.35
        _UseSceneTextures("Soft intersections enabled",Float)=1
    }
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+5" "RenderPipeline"="UniversalPipeline"}
        Pass
        {
            Tags {"LightMode"="UniversalForward"}
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "WaterCommon.hlsl"
            TEXTURE2D(_NoiseMap);SAMPLER(sampler_NoiseMap);
            TEXTURE2D(_NormalMap);SAMPLER(sampler_NormalMap);
            CBUFFER_START(UnityPerMaterial)
            half4 _WaterColor,_FoamColor;
            float _FallSpeed,_Density,_StreakScale,_Turbulence,_SoftDepth,_UseSceneTextures;
            CBUFFER_END
            struct A {float4 positionOS:POSITION;float3 normalOS:NORMAL;float2 uv:TEXCOORD0;float2 stage:TEXCOORD1;};
            struct V {float4 positionCS:SV_POSITION;float3 positionWS:TEXCOORD0;half3 normalWS:TEXCOORD1;float2 uv:TEXCOORD2;float2 stage:TEXCOORD3;half fog:TEXCOORD4;};
            V Vert(A i)
            {
                V o;float p=i.stage.y;
                i.positionOS.xyz+=i.normalOS*sin(i.uv.x*2.1+i.uv.y*2.8-_Time.y*5.3)*_Turbulence*smoothstep(0,.15,p)*(.3+.7*p);
                VertexPositionInputs pos=GetVertexPositionInputs(i.positionOS.xyz);o.positionCS=pos.positionCS;o.positionWS=pos.positionWS;
                o.normalWS=TransformObjectToWorldNormal(i.normalOS);o.uv=i.uv;o.stage=i.stage;o.fog=ComputeFogFactor(pos.positionCS.z);return o;
            }
            half4 Frag(V i):SV_Target
            {
                float2 p=float2(i.uv.x*_StreakScale*.23,i.uv.y*.035-_Time.y*_FallSpeed*.035);
                p.x+=sin(i.uv.y*.65-_Time.y*1.4)*.025*smoothstep(0,.3,i.stage.y);
                float4 n=SAMPLE_TEXTURE2D(_NoiseMap,sampler_NoiseMap,p);
                float fine=SAMPLE_TEXTURE2D(_NoiseMap,sampler_NoiseMap,p*float2(2.4,2)+float2(.17,-_Time.y*.1)).g;
                float ribbons=smoothstep(.28,.69,n.r*.75+fine*.25);
                float froth=smoothstep(.34,.77,n.b*.55+fine*.45);
                float top=1-smoothstep(0,.16,i.stage.y);
                float bottom=smoothstep(.45,1,i.stage.y);
                float foam=saturate(.06+ribbons*.43+froth*.12+top*.58+bottom*.28);
                half3 normal=normalize(i.normalWS);half3 view=SafeNormalize(GetWorldSpaceViewDir(i.positionWS));
                float fresnel=pow(1-abs(dot(normal,view)),3);
                Light light=GetMainLight();float lit=.65+.35*abs(dot(normal,light.direction));
                half3 col=lerp(_WaterColor.rgb,_FoamColor.rgb,foam)*lit;
                col+=light.color*fresnel*.09;
                float alpha=_Density*lerp(.2,1,ribbons)*lerp(.7,1,fine);
                alpha=lerp(alpha,_Density*.85,top);
                alpha*=1-smoothstep(.91,1,i.stage.y);
                if(_UseSceneTextures>.5)
                {
                    float scene=WaterEyeDepth(SampleSceneDepth(GetNormalizedScreenSpaceUV(i.positionCS)));
                    float own=-TransformWorldToView(i.positionWS).z;
                    alpha*=saturate((scene-own)/max(_SoftDepth,.001));
                }
                clip(alpha-.025);
                return half4(MixFog(col,i.fog),alpha);
            }
            ENDHLSL
        }
    }
}
