Shader "Custom/Glass"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Transparency ("Transparency", Range(0, 1)) = 0.5
        _RefractionStrength ("Refraction Strength", Range(0, 0.1)) = 0.02
        _ReflectionCube ("Reflection HDR Cubemap", Cube) = "white" {}
        _ReflectionStrength ("Reflection Strength", Range(0, 1)) = 0.5
        _FresnelPower ("Fresnel Power", Range(0.1, 10)) = 3

        [Header(Normal Map)]
        [Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalScale ("Normal Scale", Range(0, 4)) = 1

        [Header(Highlight)]
        _HighlightColor ("Highlight Color", Color) = (1, 1, 1, 1)
        _Shininess ("Shininess", Range(1, 256)) = 32
        _HighlightStrength ("Highlight Strength", Range(0, 5)) = 1

        [Header(Anisotropy)]
        _Anisotropy ("Anisotropy Blend", Range(0, 1)) = 0.5
        _AnisotropyDirection ("Anisotropy Direction", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "GlassForward"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float3 tangentWS  : TEXCOORD3;
                float3 bitangentWS: TEXCOORD4;
                float4 screenPos  : TEXCOORD5;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float  _Transparency;
                float  _RefractionStrength;
                float  _ReflectionStrength;
                float  _FresnelPower;
                float4 _NormalMap_ST;
                float  _NormalScale;
                float4 _HighlightColor;
                float  _Shininess;
                float  _HighlightStrength;
                float  _Anisotropy;
                float  _AnisotropyDirection;
            CBUFFER_END

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURECUBE(_ReflectionCube);
            SAMPLER(sampler_ReflectionCube);

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs posInputs  = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                output.normalWS   = normInputs.normalWS;
                output.tangentWS  = normInputs.tangentWS;
                output.bitangentWS= normInputs.bitangentWS;
                output.uv         = input.uv;
                output.screenPos  = ComputeScreenPos(posInputs.positionCS);
                return output;
            }

            // 从法线贴图得到世界空间法线
            float3 ApplyNormalMap(float2 uv, float3 N, float3 T, float3 B, float scale)
            {
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), scale);
                float3 nWS = normalize(T * nTS.x + B * nTS.y + N * nTS.z);
                return nWS;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // ---------- 世界空间基向量 ----------
                float3 N = normalize(input.normalWS);
                float3 T = input.tangentWS;
                float  tLen = length(T);
                T = tLen > 1e-4 ? T / tLen : normalize(cross(N, float3(0, 1, 0)));
                float3 B = input.bitangentWS;
                B = length(B) > 1e-4 ? normalize(B) : normalize(cross(N, T));

                // ---------- 采样法线贴图 ----------
                float2 normalUV = input.uv * _NormalMap_ST.xy + _NormalMap_ST.zw;
                float3 normalWS = ApplyNormalMap(normalUV, N, T, B, _NormalScale);

                float3 viewDirWS = normalize(GetWorldSpaceViewDir(input.positionWS));

                // ---------- 菲涅尔（用扰动后的法线） ----------
                float NdotV = saturate(dot(normalWS, viewDirWS));
                float fresnel = pow(1.0 - NdotV, _FresnelPower);

                // ---------- 折射 ----------
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float2 refractOffset = normalWS.xy * _RefractionStrength;
                float2 refractUV = screenUV + refractOffset;
                half3 refractedColor = SampleSceneColor(refractUV);

                // ---------- 反射 (HDR Cubemap) ----------
                float3 reflectDir = reflect(-viewDirWS, normalWS);
                half3 reflectionColor = SAMPLE_TEXTURECUBE_LOD(_ReflectionCube, sampler_ReflectionCube, reflectDir, 0).rgb;
                reflectionColor *= _ReflectionStrength;

                // ---------- 各向异性高光 ----------
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float3 H = normalize(lightDir + viewDirWS);

                // 按 _AnisotropyDirection 旋转切线
                float angle = _AnisotropyDirection * PI * 2.0;
                float sinA, cosA;
                sincos(angle, sinA, cosA);
                float3 rotatedT = normalize(T * cosA + B * sinA);

                float NoH = saturate(dot(normalWS, H));
                float specIso = pow(NoH, _Shininess);

                float ToH = dot(rotatedT, H);
                float sinTH = sqrt(saturate(1.0 - ToH * ToH));
                float specAniso = pow(sinTH, _Shininess);

                float spec = lerp(specIso, specAniso, _Anisotropy) * _HighlightStrength;
                half3 highlight = _HighlightColor.rgb * mainLight.color * spec;

                // ---------- 最终颜色 ----------
                half3 baseColor = _BaseColor.rgb;
                half3 finalColor = lerp(refractedColor, baseColor, _Transparency * (1 - fresnel));
                finalColor += reflectionColor * fresnel;
                finalColor += highlight;

                float alpha = _Transparency;
                return half4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}