Shader "Wasteland/Violet Rift Volume"
{
    Properties
    {
        [NoScaleOffset] _FlowNoise ("流动噪声贴图 (FlowField)", 2D) = "gray" {}
        _Thickness ("门体厚度（米）", Range(0.3,2.65)) = 1.55
        _Spacing ("门内层间距", Range(0.2,1.3)) = 1
        [HDR] _RimColor ("门沿 · 粉紫", Color) = (1,0.17,1.4,1)
        _RimWarp ("门沿扭曲", Range(0,2.5)) = 0.9
        [HDR] _WallColor ("内壁 · 紫罗兰", Color) = (0.31,0.075,0.88,1)
        _WallWarp ("内壁旋涡扭曲", Range(-3,3)) = 1
        [HDR] _FrontColor ("近层 · 淡紫流光", Color) = (0.54,0.16,0.95,1)
        _FrontWarp ("近层扭曲", Range(-3,3)) = 1.2
        [HDR] _MiddleColor ("中层 · 冰蓝流光", Color) = (0.09,0.4,1.16,1)
        _MiddleWarp ("中层扭曲", Range(-3,3)) = 1.7
        [HDR] _RearColor ("深层 · 靛蓝流光", Color) = (0.26,0.12,1.15,1)
        _RearWarp ("深层扭曲", Range(-3,3)) = 2
        [HDR] _SparkColor ("光点 · 冷白", Color) = (1.25,0.93,1.45,1)
        [HDR] _CoreColor ("门心底色", Color) = (0.015,0.004,0.042,1)
        _CoreDensity ("门心浓度", Range(0,3.0)) = 1.35
        [HDR] _SmokeColor ("外围雾色", Color) = (0.009,0.005,0.016,1)
        _SmokeDensity ("黑雾浓度", Range(0,3.0)) = 1.27
        _SmokeWarp ("黑雾扭曲", Range(0,3)) = 1.32
        _Spin ("黑雾旋转速度", Range(-3,3)) = 1
        _Inflow ("黑雾向内流速", Range(0,4)) = 1.35
        _EnergySpeed ("门内流光速度", Range(0,3)) = 1
        _Emission ("发光强度", Range(0,4)) = 1.1
        _Steps ("体积采样（默认 64）", Range(32,96)) = 64
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent+5" "DisableBatching"="True" }
        Pass
        {
            Name "RiftVolume"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite Off
            ZTest Always
            Blend One OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _Thickness;
                float _Spacing;
                float4 _RimColor;
                float _RimWarp;
                float4 _WallColor;
                float _WallWarp;
                float4 _FrontColor;
                float _FrontWarp;
                float4 _MiddleColor;
                float _MiddleWarp;
                float4 _RearColor;
                float _RearWarp;
                float4 _SparkColor;
                float4 _CoreColor;
                float _CoreDensity;
                float4 _SmokeColor;
                float _SmokeDensity;
                float _SmokeWarp;
                float _Spin;
                float _Inflow;
                float _EnergySpeed;
                float _Emission;
                float _Steps;
            CBUFFER_END
            TEXTURE2D(_FlowNoise);
            SAMPLER(sampler_FlowNoise);
            float4 riftNoise(float2 uv) { return SAMPLE_TEXTURE2D_LOD(_FlowNoise,sampler_FlowNoise,uv,0); }
#ifndef WASTELAND_RIFT_VOLUME_INCLUDED
#define WASTELAND_RIFT_VOLUME_INCLUDED

// All distances below are in an elliptical coordinate system. The two mouths
// are at z = +/-0.68. The local-to-world scale converts this to metres.
static const float tau = 6.28318530718;

float2 turn(float phase) { return float2(cos(phase), sin(phase)); }
float bell(float x) { return exp2(-min(x*x, 80.0)); }
float seed(float v) { return frac(sin(v*63.616+14.71)*4375.584); }

// A moving packet within each angular lane produces long tails and compact heads.
// Integer lane counts keep the polar map continuous across the angle seam.
float2 motes(float radius, float angle, float time, float phase, float lanes)
{
    float u = frac(angle/tau + phase) * lanes;
    float lane = floor(u);
    float dice = seed(lane + phase*117.0);
    float crossLane = (frac(u)-0.5) / (0.035 + 0.055*dice);
    float flight = frac(radius*1.72 + time*(0.23+0.10*dice) + dice*13.7) - 0.55;
    float tail = bell(crossLane) * bell(flight/(flight > 0.0 ? 0.185 : 0.038));
    float head = bell(crossLane*0.62) * bell(flight/0.025);
    return float2(tail,head) * smoothstep(0.24, 0.68, dice);
}

// Integrate a thin surface over each ray segment so turning the camera does
// not make a sheet flicker or disappear between marching samples.
float sheetWeight(float distance, float halfStep, float width)
{
    float h = max(halfStep, 0.0003);
    float lo = distance - h, hi = distance + h;
    float c0 = sign(lo)*(1.0-exp2(-abs(lo)/width));
    float c1 = sign(hi)*(1.0-exp2(-abs(hi)/width));
    return (c1-c0)*0.7213475*width/h;
}

void veil(float3 p, float3 stepVector, float radius, float angle, float clock,
          float zCenter, float curve, float layer, float warp, float3 tint,
          inout float3 emission, inout float extinction)
{
    float dist = p.z - (zCenter + curve*dot(p.xy,p.xy));
    float span = abs(stepVector.z - 2.0*curve*dot(p.xy,stepVector.xy))*0.5;
    if (abs(dist)>0.105+span || radius>1.014) return;
    float weight = sheetWeight(dist,span,0.024);
    float twist = warp*(1.90*radius - 1.18*radius*radius
                  + 0.25*sin(3.0*angle + 4.6*radius - clock*0.42 + layer));
    float a = angle + twist + 0.32*layer - clock*(0.085+layer*0.017);
    float2 fil = motes(radius,a,clock*_EnergySpeed,0.207*layer,31.0+layer*4.0);
    float2 uv = float2(a/tau, radius + clock*_EnergySpeed*0.075);
    float4 grain = riftNoise(uv*float2(3.0,0.46)+float2(layer*.21,layer*.14));
    float tendril = bell((grain.g - 0.54)*26.0) * smoothstep(0.38,0.68,grain.r);
    float dust = pow(saturate(grain.b*1.15),12.0);
    float mask = smoothstep(0.12,0.48,radius)*(1.0-smoothstep(0.93,1.015,radius));
    float light = mask*(0.032+0.19*grain.r + 1.10*tendril + dust*0.65 + 3.85*fil.x + 4.7*fil.y);
    emission += weight*(tint*light + _SparkColor.rgb*fil.y*mask*1.7)*_Emission*5.4;
    extinction += weight*(0.32+0.70*grain.r)*mask;
}

// Returns premultiplied linear radiance and opacity.
float4 traceRift(float3 origin, float3 direction, float farLimit, float clock)
{
    float3 safeDir = float3(direction.x>=0?1:-1,direction.y>=0?1:-1,direction.z>=0?1:-1)
        * max(abs(direction),0.000001);
    float3 a=(float3(-1.65,-1.65,-0.98)-origin)/safeDir;
    float3 b=(float3(1.65,1.65,0.98)-origin)/safeDir;
    float3 low=min(a,b),high=max(a,b);
    float entry=max(0.0,max(low.x,max(low.y,low.z)));
    float finish=min(farLimit,min(high.x,min(high.y,high.z)));
    if(finish<=entry) return 0;
    int count=(int)clamp(_Steps,32.0,96.0);
    float increment=(finish-entry)/count;
    float3 stepVector=increment*direction;
    float3 p=origin+direction*(entry+0.5*increment);
    float transmission=1.0;
    float3 result=0;
    [loop] for(int i=0;i<count;++i,p+=stepVector)
    {
        float r=length(p.xy);
        if(r>1.62) continue;
        float ang=atan2(p.y,p.x+1e-8);
        float z=abs(p.z);
        float3 light=0;
        float density=0;
        // Outer soot. Inverse advection samples r + t, so identifiable
        // filaments travel towards smaller radii while rotating around the lip.
        if(r>0.86 && _SmokeDensity>0.0)
        {
            float rad=r+clock*_Inflow*0.10;
            float phi=ang-clock*_Spin*0.30 + _SmokeWarp*(1.86*(r-1.0)+
                      0.38*sin(ang*3.0+r*4.0-clock*0.23+p.z*1.2));
            float2 st=float2(phi/tau,rad);
            float4 eddy=riftNoise(st*float2(2.0,0.67)+p.z*float2(0.030,0.12));
            float4 fibers=riftNoise(st*float2(7.0,0.91)+float2(eddy.g*0.065,p.z*0.16));
            float fingers=smoothstep(0.27,0.77,eddy.r*0.70+fibers.g*0.30);
            float reach=1.07 + fingers*0.52;
            float smoke=smoothstep(0.88,1.045,r)*(1.0-smoothstep(reach-0.13,reach+0.035,r));
            float smokeDepth=bell((p.z-0.13*(eddy.g-0.5))/0.53);
            float veins=0.20+1.1*smoothstep(0.29,0.71,fibers.r)*fingers;
            float soot=smoke*smokeDepth*veins*_SmokeDensity*3.1;
            density+=soot;
            light+=_SmokeColor.rgb*soot;
        }
        // Two corrugated elliptical lips with a moving pair of hot arcs and
        // a softer radiating fringe. Opposite faces have different phases.
        if(r>0.79 && r<1.25)
        {
            float side=p.z>=0?1.0:-1.0;
            float aa=ang+side*0.16;
            float wobble=_RimWarp*(0.011*sin(5*aa-clock*1.25)+0.007*sin(11*aa+clock*1.42));
            float rimRadius=0.983+wobble;
            float face=0.68+0.027*_RimWarp*sin(3*aa+clock);
            float d=r-rimRadius;
            float dz=z-face;
            float arcs=pow(saturate(0.5+0.5*cos(2*aa-1.5-clock*0.65+0.39*sin(3*aa))),3.0);
            float dr=abs(dot(p.xy/max(r,0.001),stepVector.xy))*0.5;
            float hot=sheetWeight(d,dr,(0.013+0.014*arcs)*0.77)*bell(dz/0.070);
            float threadD=d-0.040-0.015*sin(4*aa+clock*1.05);
            float thread=sheetWeight(threadD,dr,0.0058)*bell((dz+0.059)/0.062);
            float innerThread=sheetWeight(d+0.043+0.012*cos(6*aa-clock),dr,0.0069)*bell((dz+0.084)/0.07);
            float glow=bell(d/0.082)*bell(dz/0.15);
            float3 tip=lerp(_RimColor.rgb,_SparkColor.rgb,0.54*arcs);
            light+=_Emission*(tip*hot*(10.0+72.0*arcs) + _RimColor.rgb*
                     (thread*(6.0+8.0*arcs)+innerThread*4.5+glow*(1.6+4.6*arcs)));
            density+=hot*3.8+glow*1.30;
            // Oblique views reveal a twisting mantle spanning the two lips.
            float bridge=bell((r-(0.922+0.051*saturate(z/0.68)))/0.052);
            if(bridge>0.003 && z<0.69)
            {
                float sideView=1.0-abs(direction.z);
                float4 braid=riftNoise(float2(ang/tau*3.0+p.z*0.20-clock*0.044,p.z*0.61-clock*0.087));
                float gauze=bridge*(0.25+1.0*braid.r)*sideView;
                float silk=bell((braid.g-0.53)*29.0);
                light+=_WallColor.rgb*gauze*(0.75+2.9*silk)*_Emission;
                density+=gauze*1.55;
            }
        }
        if(r<1.03 && z<0.83)
        {
            // Hourglass throat. The wall radius changes along the depth axis.
            float s=saturate(z/0.68);
            float wallRadius=0.19+0.786*pow(s,0.75);
            float wall=bell((r-wallRadius)/0.083)*(1.0-smoothstep(0.66,0.79,z));
            float aWall=ang+_WallWarp*(1.7*(1.0-s)+0.18*sin(4.0*ang+4.0*s-clock*0.55));
            float4 vapor=riftNoise(float2(aWall/tau*3.0,s*0.69+clock*_EnergySpeed*0.087));
            float threads=bell((vapor.g-0.51)*23.0)*smoothstep(0.32,0.69,vapor.r);
            float shade=0.10+0.90*s;
            light+=wall*_WallColor.rgb*(0.50+1.9*vapor.r+threads*7.0)*shade*_Emission;
            density+=wall*(1.8+1.2*vapor.g);
            float core=bell(z/0.27)*(1.0-smoothstep(0.04,0.95,r));
            density+=core*_CoreDensity*6.0;
            light+=_CoreColor.rgb*core*_CoreDensity*4.2;
            veil(p,stepVector,r,ang,clock, 0.34*_Spacing, 0.17,1.0,_FrontWarp,_FrontColor.rgb,light,density);
            veil(p,stepVector,r,ang,clock,-0.015,0.07,2.0,_MiddleWarp,_MiddleColor.rgb,light,density);
            veil(p,stepVector,r,ang,clock,-0.38*_Spacing,-0.12,3.0,_RearWarp,_RearColor.rgb,light,density);
        }
        float attenuation=exp(-density*increment);
        float integral=density>0.001?(1.0-attenuation)/density:increment;
        result+=transmission*light*integral;
        transmission*=attenuation;
        if(transmission<0.007) break;
    }
    return float4(result,1.0-transmission);
}
#endif

            struct VertexInput { float4 positionOS : POSITION; };
            struct FragmentInput { float4 positionCS : SV_POSITION; float3 world : TEXCOORD0; };
            FragmentInput vert(VertexInput v)
            {
                FragmentInput o;
                float3 p=v.positionOS.xyz;
                p.z *= 2.0*0.98*_Thickness/(1.36*4.0);
                o.world=TransformObjectToWorld(p);
                o.positionCS=TransformWorldToHClip(o.world);
                return o;
            }

            float4 frag(FragmentInput i) : SV_Target
            {
                float3 dirWS=-GetWorldSpaceNormalizeViewDir(i.world);
                float3 toRift=float3(3.30,3.30,4.0*1.36/_Thickness);
                float3 perMeter=mul((float3x3)GetWorldToObjectMatrix(),dirWS)*toRift;
                float factor=max(length(perMeter),0.00001);
                float3 dir=perMeter/factor;
                float eyeDist=dot(i.world-GetCameraPositionWS(),dirWS);
                float3 origin=TransformWorldToObject(i.world)*toRift-perMeter*eyeDist;
                float2 uv=GetNormalizedScreenSpaceUV(i.positionCS);
                float depth=SampleSceneDepth(uv);
                float farLimit=eyeDist*factor+0.001;
                #if UNITY_REVERSED_Z
                    bool occupied=depth>0.000001;
                #else
                    bool occupied=depth<0.999999;
                    depth=lerp(UNITY_NEAR_CLIP_VALUE,1.0,depth);
                #endif
                if(occupied)
                {
                    float3 surface=ComputeWorldSpacePosition(uv,depth,UNITY_MATRIX_I_VP);
                    farLimit=min(farLimit,(eyeDist+dot(surface-i.world,dirWS))*factor);
                }
                return traceRift(origin,dir,farLimit,_Time.y);
            }
            ENDHLSL
        }
    }
}
