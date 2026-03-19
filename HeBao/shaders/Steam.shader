// URP Shader - Almgp/Steam URP (Fixed pow warning)
// 直接转换自Shader Forge生成的Steam着色器 - 修复pow警告

Shader "Almgp/Steam URP"
{
    Properties
    {
        _MainTex ("MainTex", 2D) = "white" {}
        _TintColor ("Color", Color) = (0.5, 0.5, 0.5, 1)
        _exponent ("exponent", Range(0.1, 8)) = 1.150583
        _Power ("Power", Range(0, 64)) = 2
        _Displace_power ("Displace_power", Range(0, 16)) = 1
        _Burn_radius ("Burn_radius", Range(0, 256)) = 0.5
        _Normal ("Normal", 2D) = "bump" {}
        _refract ("refract", Range(0, 1)) = 1
        _Refraction_blur ("Refraction_blur", Range(0, 12)) = 2
        _Refract_factor ("Refract_factor", Range(0.1, 3)) = 1.018187
        _Height_grad ("Height_grad", 2D) = "white" {}
        _height_size ("height_size", Range(0, 0.01)) = 0
        [MaterialToggle] _Use_h_grad ("Use_h_grad", Float) = 0
    }
    
    SubShader
    {
        Tags
        {
            "IgnoreProjector" = "True"
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend One One
            Cull Off
            ZWrite Off
            
            HLSLPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            // 纹理和采样器
            TEXTURE2D(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_Height_grad); SAMPLER(sampler_Height_grad);
            
            // 常量缓冲区
            CBUFFER_START(UnityPerMaterial)
                float4 _TintColor;
                float4 _MainTex_ST;
                float4 _Height_grad_ST;
                float _exponent;
                float _Power;
                float _Displace_power;
                float _Burn_radius;
                float _refract;
                float _Refraction_blur;
                float _Refract_factor;
                float _height_size;
                float _Use_h_grad;
            CBUFFER_END
            
            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 texcoord0 : TEXCOORD0;
                float4 vertexColor : COLOR;
            };
            
            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
                float2 uv0 : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 vertexColor : COLOR;
                float4 screenPos : TEXCOORD3;
                float fogFactor : TEXCOORD4;
            };
            
            VertexOutput vert(VertexInput v)
            {
                VertexOutput o = (VertexOutput)0;
                
                o.uv0 = v.texcoord0;
                o.vertexColor = v.vertexColor;
                
                // 计算世界空间法线
                o.normalWS = TransformObjectToWorldNormal(v.normal);
                
                // 应用位移
                v.vertex.xyz += v.normal * _Displace_power;
                
                // 计算世界空间位置
                o.positionWS = TransformObjectToWorld(v.vertex.xyz);
                
                // 计算裁剪空间位置
                o.positionCS = TransformWorldToHClip(o.positionWS);
                
                // 计算屏幕空间位置
                o.screenPos = ComputeScreenPos(o.positionCS);
                
                // 计算雾因子
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                
                return o;
            }
            
            float4 frag(VertexOutput i, float facing : VFACE) : SV_Target
            {
                // 处理双面渲染
                float faceSign = (facing >= 0) ? 1 : -1;
                i.normalWS = normalize(i.normalWS) * faceSign;
                
                // 计算视图方向
                float3 viewDirection = normalize(GetCameraPositionWS() - i.positionWS);
                float3 normalDirection = i.normalWS;
                
                // 深度计算
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float sceneZ = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;
                float sceneLinear = LinearEyeDepth(sceneZ, _ZBufferParams);
                float partLinear = i.screenPos.z;
                float depthDiff = max(0, sceneLinear - partLinear);
                float edgeFactor = saturate(1.0 - saturate(depthDiff / max(0.001, _Burn_radius)));
                
                // 采样主纹理
                float4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv0 * _MainTex_ST.xy + _MainTex_ST.zw);
                
                // 修复：计算菲涅尔时确保底数非负
                float ndv = dot(normalDirection, viewDirection);
                float fresnelBase = 1.0 - max(0, ndv);
                fresnelBase = max(0, fresnelBase); // 确保非负
                float fresnel = pow(fresnelBase, _exponent);
                
                // 组合因子
                float combined = fresnel + edgeFactor;
                
                // 基础颜色计算
                float3 baseColor = mainTex.rgb * i.vertexColor.rgb * _TintColor.rgb * _Power * combined;
                float3 saturatedColor = saturate(baseColor);
                
                // 高度渐变采样
                float2 uvHeight = float2(1.0, i.positionWS.y) * _height_size;
                float2 uvHeightTrans = uvHeight * _Height_grad_ST.xy + _Height_grad_ST.zw;
                float heightGrad = SAMPLE_TEXTURE2D_LOD(_Height_grad, sampler_Height_grad, uvHeightTrans, 0).r;
                
                // 最终颜色
                float3 finalColor = lerp(saturatedColor, baseColor * heightGrad, _Use_h_grad);
                
                // 应用雾效
                finalColor = MixFog(finalColor, i.fogFactor);
                
                return float4(finalColor, 1);
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "UnityEditor.ShaderGUI"
}