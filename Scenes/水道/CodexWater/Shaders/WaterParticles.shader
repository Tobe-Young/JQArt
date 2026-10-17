Shader "Codex Water/Soft Spray URP"
{
    Properties
    {
        _BaseMap("Soft particle",2D)="white"{}
        _BaseColor("Tint",Color)=(.78,.93,.94,.65)
        _SoftDistance("Depth softness",Float)=.45
        _UseSceneTextures("Soft intersections enabled",Float)=1
    }
    SubShader
    {
        Tags {"Queue"="Transparent+10" "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline"}
        Pass
        {
            Tags {"LightMode"="UniversalForward"}
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "WaterCommon.hlsl"
            TEXTURE2D(_BaseMap);SAMPLER(sampler_BaseMap);
            CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;float _SoftDistance,_UseSceneTextures;
            CBUFFER_END
            struct A{float4 positionOS:POSITION;half4 color:COLOR;float2 uv:TEXCOORD0;};
            struct V{float4 positionCS:SV_POSITION;half4 color:COLOR;float2 uv:TEXCOORD0;float3 positionWS:TEXCOORD1;half fog:TEXCOORD2;};
            V Vert(A i){V o;VertexPositionInputs p=GetVertexPositionInputs(i.positionOS.xyz);o.positionCS=p.positionCS;o.positionWS=p.positionWS;o.color=i.color*_BaseColor;o.uv=i.uv;o.fog=ComputeFogFactor(p.positionCS.z);return o;}
            half4 Frag(V i):SV_Target
            {
                half4 c=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,i.uv)*i.color;
                if(_UseSceneTextures>.5){float depth=WaterEyeDepth(SampleSceneDepth(GetNormalizedScreenSpaceUV(i.positionCS)));c.a*=saturate((depth+TransformWorldToView(i.positionWS).z)/max(_SoftDistance,.001));}
                Light l=GetMainLight();c.rgb*=.75+.25*saturate(l.color);c.rgb=MixFog(c.rgb,i.fog);return c;
            }
            ENDHLSL
        }
    }
}
