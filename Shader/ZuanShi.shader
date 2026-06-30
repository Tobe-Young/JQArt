Shader "Mobile/DiamondSSR"
{
    Properties
    {
        [MainTexture] _MainTex ("Base Texture", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        
        [Header(Normal Map)]
        [Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalScale ("Normal Scale", Range(0, 2)) = 1.0
        
        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (0.5, 0.8, 1, 1)
        _RimPower ("Rim Power", Range(0.5, 8.0)) = 3.0
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 1.0
        
        [Header(Sparkle)]
        _SparkleColor ("Sparkle Color", Color) = (1, 1, 1, 1)
        _SparkleDensity ("Sparkle Density", Range(1, 50)) = 20
        _SparkleSize ("Sparkle Size", Range(0.01, 0.1)) = 0.03
        _SparkleSpeed ("Sparkle Speed", Range(0, 1)) = 0.2
        _SparkleIntensity ("Sparkle Intensity", Range(0, 100)) = 2.0
        _SparkleNormalInfluence ("Sparkle Normal Influence", Range(0, 1)) = 0.3
        
        [Header(Refraction)]
        _RefractionStrength ("Refraction Strength", Range(0, 0.5)) = 0.1
        _FresnelPower ("Fresnel Power", Range(0.5, 5)) = 2.0
        
        [Header(Environment Reflection)]
        _CubeMap ("Cube Map", Cube) = "" {}
        _EnvIntensity ("Environment Intensity", Range(0, 3)) = 1.5
        _EnvTint ("Environment Tint", Color) = (1, 1, 1, 1)
        _ReflectionMipLevel ("Reflection Mip Level", Range(0, 7)) = 1
        _ReflectionBlendMode ("Reflection Blend Mode", Range(0, 1)) = 1
        
        [Header(Advanced Reflection)]
        _ReflectionPower ("Reflection Power", Range(0.1, 3)) = 1.2
        _ReflectionContrast ("Reflection Contrast", Range(0.5, 3)) = 1.5
        _MultiReflectionLayers ("Multi Reflection Layers", Range(1, 5)) = 2
        _ReflectionSpread ("Reflection Spread", Range(0, 0.5)) = 0.1
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Transparent" 
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }
        
        LOD 200
        
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // 移动端优化
            #pragma target 3.0
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            // 顶点输入结构
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            // 片段输入结构
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float2 normalUV : TEXCOORD4;
                float4 screenPos : TEXCOORD5;
                float3 viewDirWS : TEXCOORD6;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            // 纹理采样器
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            
            TEXTURECUBE(_CubeMap);
            SAMPLER(sampler_CubeMap);
            
            // 屏幕空间纹理
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _NormalMap_ST;
                half4 _BaseColor;
                half _NormalScale;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half4 _SparkleColor;
                half _SparkleDensity;
                half _SparkleSize;
                half _SparkleSpeed;
                half _SparkleIntensity;
                half _SparkleNormalInfluence;
                half _RefractionStrength;
                half _FresnelPower;
                half4 _EnvTint;
                half _EnvIntensity;
                half _ReflectionMipLevel;
                half _ReflectionBlendMode;
                half _ReflectionPower;
                half _ReflectionContrast;
                half _MultiReflectionLayers;
                half _ReflectionSpread;
            CBUFFER_END
            
            // 简单的伪随机函数
            half Random(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
            }
            
            // 价值噪声（用于闪光效果）
            half ValueNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                f = f * f * (3.0 - 2.0 * f);
                
                half a = Random(i);
                half b = Random(i + float2(1, 0));
                half c = Random(i + float2(0, 1));
                half d = Random(i + float2(1, 1));
                
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }
            
            // 增强反射对比度
            half3 EnhanceReflection(half3 reflection, half contrast, half power)
            {
                // 增加对比度
                half3 enhanced = (reflection - 0.5) * contrast + 0.5;
                // 增强亮度
                enhanced = pow(max(enhanced, 0.0), power);
                return saturate(enhanced);
            }
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                output.viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.normalUV = TRANSFORM_TEX(input.uv, _NormalMap);
                output.screenPos = ComputeScreenPos(output.positionCS);
                
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                // 采样法线贴图
                half4 normalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.normalUV);
                half3 normalTS = UnpackNormalScale(normalMap, _NormalScale);
                
                // 构建TBN矩阵
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = normalize(cross(normalWS, tangentWS) * input.tangentWS.w);
                float3x3 TBN = float3x3(tangentWS, bitangentWS, normalWS);
                
                // 转换法线到世界空间
                float3 perturbedNormalWS = normalize(mul(normalTS, TBN));
                
                // 混合顶点法线和贴图法线
                float3 finalNormalWS = perturbedNormalWS;
                
                // 基础纹理采样
                half4 baseMap = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                half4 baseColor = baseMap * _BaseColor;
                
                // 标准化向量
                float3 viewDirWS = normalize(input.viewDirWS);
                float3 lightDirWS = normalize(GetMainLight().direction);
                
                // 1. Fresnel效果（使用扰动后的法线）
                half fresnel = pow(1.0 - saturate(dot(finalNormalWS, viewDirWS)), _FresnelPower);
                
                // ===== 2. 增强的环境反射系统 =====
                half3 environmentReflection = half3(0, 0, 0);
                
                // 主反射方向
                float3 reflectDir = reflect(-viewDirWS, finalNormalWS);
                
                // 多层反射采样（模拟钻石内部的多次反射）
                [unroll]
                for(int i = 0; i < 3; i++) // 限制最多3层以保证性能
                {
                    if(i < (int)_MultiReflectionLayers)
                    {
                        // 每层使用略微不同的反射方向和mip级别
                        float layerBlend = (float)i / max(_MultiReflectionLayers - 1, 1);
                        float3 layerReflectDir = reflectDir;
                        
                        // 为每层添加微小偏移
                        if(i > 0)
                        {
                            float3 randomOffset = float3(
                                ValueNoise(input.uv * (i + 1) + _Time.y * 0.1) - 0.5,
                                ValueNoise(input.uv * (i + 1) + _Time.y * 0.1 + 0.5) - 0.5,
                                ValueNoise(input.uv * (i + 1) + _Time.y * 0.1 + 1.0) - 0.5
                            ) * _ReflectionSpread;
                            
                            layerReflectDir = normalize(reflectDir + randomOffset);
                        }
                        
                        // 采样cubemap，使用不同的mip级别
                        half mipLevel = _ReflectionMipLevel + i * 1.5;
                        half4 layerReflection = SAMPLE_TEXTURECUBE_LOD(
                            _CubeMap, 
                            sampler_CubeMap, 
                            layerReflectDir, 
                            mipLevel
                        );
                        
                        // 每层的强度递减
                        half layerIntensity = 1.0 - layerBlend * 0.5;
                        environmentReflection += layerReflection.rgb * layerIntensity;
                    }
                }
                
                // 平均多层反射
                environmentReflection /= max(_MultiReflectionLayers, 1);
                
                // 增强反射对比度和亮度
                environmentReflection = EnhanceReflection(
                    environmentReflection, 
                    _ReflectionContrast, 
                    _ReflectionPower
                );
                
                // 应用色调
                environmentReflection *= _EnvTint.rgb;
                
                // 基于视角的反射强度（菲涅尔效果）
                half reflectionStrength = _EnvIntensity * fresnel;
                
                // 添加额外的边缘反射增强
                half edgeReflectionBoost = pow(fresnel, 0.5) * 0.5;
                reflectionStrength += edgeReflectionBoost;
                
                // ===== 3. 屏幕空间折射 =====
                float2 screenUV = input.screenPos.xy / max(input.screenPos.w, 0.0001);
                float2 distortionOffset = finalNormalWS.xy * _RefractionStrength * (fresnel * 0.8 + 0.2);
                float2 distortedUV = screenUV + distortionOffset;
                distortedUV = saturate(distortedUV);
                
                half4 screenColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, distortedUV);
                
                // ===== 4. 边缘光 =====
                half rim = 1.0 - saturate(dot(finalNormalWS, viewDirWS));
                rim = pow(rim, _RimPower);
                
                // 边缘光也受环境反射影响
                half3 rimLight = _RimColor.rgb * rim * _RimIntensity;
                
                // ===== 5. 闪光效果 =====
                float2 sparkleUV = distortedUV * _SparkleDensity;
                float time = _Time.y * _SparkleSpeed;
                
                float2 normalOffset = finalNormalWS.xy * _SparkleNormalInfluence;
                sparkleUV += normalOffset * 0.5;
                
                half sparkle1 = ValueNoise(sparkleUV + time);
                half sparkle2 = ValueNoise(sparkleUV * 2.0 - time * 1.3);
                half sparkle3 = ValueNoise(sparkleUV * 4.0 + time * 0.7);
                
                half sparkle = sparkle1 * 0.5 + sparkle2 * 0.3 + sparkle3 * 0.2;
                sparkle = pow(saturate(sparkle), 8.0);
                
                half normalVariation = length(normalTS.xy) * 2.0;
                sparkle *= (1.0 + normalVariation * _SparkleNormalInfluence);
                
                half viewDependentSparkle = sparkle * (0.3 + fresnel * 0.7);
                half3 sparkleColor = _SparkleColor.rgb * viewDependentSparkle * _SparkleIntensity;
                
                // ===== 6. 光照计算 =====
                Light mainLight = GetMainLight();
                half3 lightColor = mainLight.color;
                
                half NdotL = saturate(dot(finalNormalWS, lightDirWS));
                half halfLambert = NdotL * 0.5 + 0.5;
                half3 diffuse = baseColor.rgb * lightColor * halfLambert * 0.3;
                
                float3 halfDir = normalize(lightDirWS + viewDirWS);
                half specular = pow(saturate(dot(finalNormalWS, halfDir)), 128);
                half specularDetail = specular * (1.0 + normalVariation * 0.8);
                half3 specularColor = lightColor * specularDetail * 1.0;
                
                // ===== 7. 最终合成 =====
                half3 finalColor = half3(0, 0, 0);
                
                // 基础层：背景折射
                finalColor = lerp(screenColor.rgb, baseColor.rgb, 0.2);
                
                // 环境反射层（显著增强）
                if(_ReflectionBlendMode > 0.5)
                {
                    // 叠加混合模式，让反射更明显
                    finalColor = finalColor + environmentReflection * reflectionStrength;
                }
                else
                {
                    // 标准混合
                    finalColor = lerp(finalColor, environmentReflection, reflectionStrength);
                }
                
                // 添加光照（降低强度，让环境反射更突出）
                finalColor += diffuse * 0.3;
                finalColor += specularColor * 0.6;
                
                // 添加边缘光
                finalColor += rimLight * 1.2;
                
                // 添加闪光
                finalColor += sparkleColor;
                
                // 最终的反射增强：在边缘区域进一步加强环境反射
                finalColor = lerp(finalColor, environmentReflection, fresnel * _EnvIntensity * 0.3);
                
                // Alpha值
                half alpha = baseColor.a;
                alpha = saturate(alpha + fresnel * 0.2);
                
                // 确保颜色值在合理范围内
                finalColor = saturate(finalColor);
                
                return half4(finalColor, alpha);
            }
            ENDHLSL
        }
        
        // 阴影投射Pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            
            float3 _LightDirection;
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif
                
                output.positionCS = positionCS;
                return output;
            }
            
            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }
    
    FallBack "Universal Render Pipeline/Unlit"
}
