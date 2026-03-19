// URP Shader - Almgp/Nuke URP
// 直接转换自Shader Forge生成的Nuke着色器

Shader "Almgp/Nuke URP"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _tesselation_factor ("tesselation_factor", Range(1, 32)) = 6.564103
        _Emmis ("Emmis", 2D) = "white" {}
        _Speed ("Speed", Range(-10, 10)) = -0.5
        _U ("U", Range(-16, 16)) = 2.225862
        _V ("V", Range(-16, 16)) = 1.556958
        _Displace_min ("Displace_min", Range(-2, 2)) = -0.2169179
        _Displace_max ("Displace_max", Range(-2, 2)) = 0.05286796
        _Height_map ("Height_map", 2D) = "white" {}
        _Speed2 ("Speed 2", Range(-10, 10)) = 0.3
        _blur ("blur", Range(0, 12)) = 2.402375
        _Gradient ("Gradient", 2D) = "white" {}
        _emmis_exp ("emmis_exp", Range(0.1, 5)) = 0.4307254
        _Emmis_power ("Emmis_power", Range(0, 512)) = 2.967281
        _Steam_blend ("Steam_blend", Range(0, 1)) = 0.5857007
        _steam_cloud_color ("steam_cloud_color", Color) = (0.5,0.5,0.5,1)
        _Opacity ("Opacity", Range(0, 1)) = 1
        [HideInInspector] _Cutoff ("Alpha cutoff", Range(0,1)) = 0.5
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
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back
            
            HLSLPROGRAM
            
            #pragma vertex tessvert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag
            #pragma require tessellation
            #pragma target 4.5
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // 纹理和采样器
            TEXTURE2D(_Height_map); SAMPLER(sampler_Height_map);
            TEXTURE2D(_Gradient); SAMPLER(sampler_Gradient);
            
            // 常量缓冲区
            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _steam_cloud_color;
                float _tesselation_factor;
                float _Speed;
                float _U;
                float _V;
                float _Displace_min;
                float _Displace_max;
                float _Speed2;
                float _blur;
                float _emmis_exp;
                float _Emmis_power;
                float _Steam_blend;
                float _Opacity;
                float4 _Height_map_ST;
                float4 _Gradient_ST;
            CBUFFER_END
            
            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 texcoord0 : TEXCOORD0;
            };
            
            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
                float2 uv0 : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
            };
            
            struct TessVertex
            {
                float4 vertex : INTERNALTESSPOS;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 texcoord0 : TEXCOORD0;
            };
            
            struct OutputPatchConstant
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };
            
            TessVertex tessvert(VertexInput v)
            {
                TessVertex o;
                o.vertex = v.vertex;
                o.normal = v.normal;
                o.tangent = v.tangent;
                o.texcoord0 = v.texcoord0;
                return o;
            }
            
            void displacement(inout VertexInput v)
            {
                float4 node_8028 = _Time;
                
                float2 node_7413 = float2((v.texcoord0.r * _U), (v.texcoord0.g * _V));
                float2 node_3673 = node_7413 + (node_8028.r * _Speed) * float2(0, 1);
                
                float4 _Height = SAMPLE_TEXTURE2D_LOD(_Height_map, sampler_Height_map, 
                    node_3673 * _Height_map_ST.xy + _Height_map_ST.zw, _blur);
                
                float2 node_8058 = (node_7413 + (node_8028.r * _Speed2) * float2(0, 1)) * 1.3;
                float4 _node_1646 = SAMPLE_TEXTURE2D_LOD(_Height_map, sampler_Height_map, 
                    node_8058 * _Height_map_ST.xy + _Height_map_ST.zw, _blur);
                
                float node_9257 = _node_1646.r > 0.5 ? 
                    (1.0 - (1.0 - 2.0 * (_node_1646.r - 0.5)) * (1.0 - _Height.r)) : 
                    (2.0 * _node_1646.r * _Height.r);
                
                float node_9888 = 0.0;
                float displacementValue = _Displace_min + ((node_9257 - node_9888) * (_Displace_max - _Displace_min)) / (1.0 - node_9888);
                v.vertex.xyz += v.normal * displacementValue;
            }
            
            float TessellationFactor(TessVertex v)
            {
                return _tesselation_factor;
            }
            
            float4 TessellationFactors(TessVertex v0, TessVertex v1, TessVertex v2)
            {
                float tv = TessellationFactor(v0);
                float tv1 = TessellationFactor(v1);
                float tv2 = TessellationFactor(v2);
                return float4(tv1 + tv2, tv2 + tv, tv + tv1, tv + tv1 + tv2) / float4(2, 2, 2, 3);
            }
            
            OutputPatchConstant hullconst(InputPatch<TessVertex, 3> v)
            {
                OutputPatchConstant o = (OutputPatchConstant)0;
                float4 ts = TessellationFactors(v[0], v[1], v[2]);
                o.edge[0] = ts.x;
                o.edge[1] = ts.y;
                o.edge[2] = ts.z;
                o.inside = ts.w;
                return o;
            }
            
            [domain("tri")]
            [partitioning("fractional_odd")]
            [outputtopology("triangle_cw")]
            [patchconstantfunc("hullconst")]
            [outputcontrolpoints(3)]
            TessVertex hull(InputPatch<TessVertex, 3> v, uint id : SV_OutputControlPointID)
            {
                return v[id];
            }
            
            [domain("tri")]
            VertexOutput domain(OutputPatchConstant tessFactors, 
                const OutputPatch<TessVertex, 3> vi, float3 bary : SV_DomainLocation)
            {
                VertexInput v = (VertexInput)0;
                
                v.vertex = vi[0].vertex * bary.x + vi[1].vertex * bary.y + vi[2].vertex * bary.z;
                v.normal = vi[0].normal * bary.x + vi[1].normal * bary.y + vi[2].normal * bary.z;
                v.tangent = vi[0].tangent * bary.x + vi[1].tangent * bary.y + vi[2].tangent * bary.z;
                v.texcoord0 = vi[0].texcoord0 * bary.x + vi[1].texcoord0 * bary.y + vi[2].texcoord0 * bary.z;
                
                displacement(v);
                
                VertexOutput o;
                o.uv0 = v.texcoord0;
                o.normalWS = TransformObjectToWorldNormal(v.normal);
                o.positionWS = TransformObjectToWorld(v.vertex.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                
                return o;
            }
            
            float4 frag(VertexOutput i) : SV_Target
            {
                i.normalWS = normalize(i.normalWS);
                float3 viewDirection = normalize(GetCameraPositionWS() - i.positionWS);
                float3 normalDirection = i.normalWS;
                
                // Emissive计算 - 完全保持原版逻辑
                float4 node_8028 = _Time;
                
                float2 node_7413 = float2((i.uv0.r * _U), (i.uv0.g * _V));
                float2 node_3673 = node_7413 + (node_8028.r * _Speed) * float2(0, 1);
                
                float4 _Height = SAMPLE_TEXTURE2D_LOD(_Height_map, sampler_Height_map, 
                    node_3673 * _Height_map_ST.xy + _Height_map_ST.zw, _blur);
                
                float2 node_8058 = (node_7413 + (node_8028.r * _Speed2) * float2(0, 1)) * 1.3;
                float4 _node_1646 = SAMPLE_TEXTURE2D_LOD(_Height_map, sampler_Height_map, 
                    node_8058 * _Height_map_ST.xy + _Height_map_ST.zw, _blur);
                
                float node_9257 = _node_1646.r > 0.5 ? 
                    (1.0 - (1.0 - 2.0 * (_node_1646.r - 0.5)) * (1.0 - _Height.r)) : 
                    (2.0 * _node_1646.r * _Height.r);
                
                float2 node_7539 = float2(0.0, saturate(pow(max(0.0, node_9257), _emmis_exp)));
                
                float4 gradientVar = SAMPLE_TEXTURE2D(_Gradient, sampler_Gradient, 
                    node_7539 * _Gradient_ST.xy + _Gradient_ST.zw);
                
                float3 node_4020 = clamp(_Emmis_power, 0.15, 512) * gradientVar.rgb * node_9257;
                
                float2 node_8435 = node_3673 * 0.6;
                float4 _node_9902 = SAMPLE_TEXTURE2D(_Height_map, sampler_Height_map, 
                    node_8435 * _Height_map_ST.xy + _Height_map_ST.zw);
                
                float3 emissive = _Color.rgb * lerp(node_4020, 
                    (_node_9902.rgb * _steam_cloud_color.rgb) + node_4020, _Steam_blend);
                
                return float4(emissive, _Opacity);
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
            Cull Back
            
            HLSLPROGRAM
            
            #pragma vertex tessvert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment fragShadow
            #pragma require tessellation
            #pragma target 4.5
            
            #pragma multi_compile_shadowcaster
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            TEXTURE2D(_Height_map); SAMPLER(sampler_Height_map);
            
            CBUFFER_START(UnityPerMaterial)
                float _tesselation_factor;
                float _Speed;
                float _U;
                float _V;
                float _Displace_min;
                float _Displace_max;
                float _Speed2;
                float _blur;
                float4 _Height_map_ST;
            CBUFFER_END
            
            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 texcoord0 : TEXCOORD0;
            };
            
            struct TessVertex
            {
                float4 vertex : INTERNALTESSPOS;
                float3 normal : NORMAL;
                float2 texcoord0 : TEXCOORD0;
            };
            
            struct OutputPatchConstant
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };
            
            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
            };
            
            TessVertex tessvert(VertexInput v)
            {
                TessVertex o;
                o.vertex = v.vertex;
                o.normal = v.normal;
                o.texcoord0 = v.texcoord0;
                return o;
            }
            
            void displacement(inout VertexInput v)
            {
                float4 node_8028 = _Time;
                float2 node_7413 = float2((v.texcoord0.r * _U), (v.texcoord0.g * _V));
                float2 node_3673 = node_7413 + (node_8028.r * _Speed) * float2(0, 1);
                
                float4 _Height = SAMPLE_TEXTURE2D_LOD(_Height_map, sampler_Height_map, 
                    node_3673 * _Height_map_ST.xy + _Height_map_ST.zw, _blur);
                
                float2 node_8058 = (node_7413 + (node_8028.r * _Speed2) * float2(0, 1)) * 1.3;
                float4 _node_1646 = SAMPLE_TEXTURE2D_LOD(_Height_map, sampler_Height_map, 
                    node_8058 * _Height_map_ST.xy + _Height_map_ST.zw, _blur);
                
                float node_9257 = _node_1646.r > 0.5 ? 
                    (1.0 - (1.0 - 2.0 * (_node_1646.r - 0.5)) * (1.0 - _Height.r)) : 
                    (2.0 * _node_1646.r * _Height.r);
                
                float node_9888 = 0.0;
                float displacementValue = _Displace_min + ((node_9257 - node_9888) * (_Displace_max - _Displace_min)) / (1.0 - node_9888);
                v.vertex.xyz += v.normal * displacementValue;
            }
            
            float TessellationFactor(TessVertex v)
            {
                return _tesselation_factor;
            }
            
            float4 TessellationFactors(TessVertex v0, TessVertex v1, TessVertex v2)
            {
                float tv = TessellationFactor(v0);
                float tv1 = TessellationFactor(v1);
                float tv2 = TessellationFactor(v2);
                return float4(tv1 + tv2, tv2 + tv, tv + tv1, tv + tv1 + tv2) / float4(2, 2, 2, 3);
            }
            
            OutputPatchConstant hullconst(InputPatch<TessVertex, 3> v)
            {
                OutputPatchConstant o = (OutputPatchConstant)0;
                float4 ts = TessellationFactors(v[0], v[1], v[2]);
                o.edge[0] = ts.x;
                o.edge[1] = ts.y;
                o.edge[2] = ts.z;
                o.inside = ts.w;
                return o;
            }
            
            [domain("tri")]
            [partitioning("fractional_odd")]
            [outputtopology("triangle_cw")]
            [patchconstantfunc("hullconst")]
            [outputcontrolpoints(3)]
            TessVertex hull(InputPatch<TessVertex, 3> v, uint id : SV_OutputControlPointID)
            {
                return v[id];
            }
            
            [domain("tri")]
            VertexOutput domain(OutputPatchConstant tessFactors, 
                const OutputPatch<TessVertex, 3> vi, float3 bary : SV_DomainLocation)
            {
                VertexInput v = (VertexInput)0;
                v.vertex = vi[0].vertex * bary.x + vi[1].vertex * bary.y + vi[2].vertex * bary.z;
                v.normal = vi[0].normal * bary.x + vi[1].normal * bary.y + vi[2].normal * bary.z;
                v.texcoord0 = vi[0].texcoord0 * bary.x + vi[1].texcoord0 * bary.y + vi[2].texcoord0 * bary.z;
                
                displacement(v);
                
                VertexOutput o;
                float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
                o.positionCS = TransformWorldToHClip(positionWS);
                
                return o;
            }
            
            float4 fragShadow(VertexOutput i) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "UnityEditor.ShaderGUI"
}