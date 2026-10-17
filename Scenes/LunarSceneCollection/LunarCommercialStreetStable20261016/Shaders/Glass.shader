Shader "LunarCollection/Street20261016/Glass" {
 Properties { _Color("Tint",Color)=(0.7,0.85,0.9,0.13) _Metallic("Metallic",Range(0,1))=0.08 _Glossiness("Smoothness",Range(0,1))=0.9 }
 SubShader {
  Tags {"Queue"="Transparent+200" "RenderType"="Transparent"}
  Cull Off ZWrite Off ZTest LEqual Blend SrcAlpha OneMinusSrcAlpha
  Pass {
   CGPROGRAM
   #pragma vertex vert
   #pragma fragment frag
   #include "UnityCG.cginc"
   fixed4 _Color;
   struct v2f {float4 pos:SV_POSITION;float3 normal:TEXCOORD0;float3 view:TEXCOORD1;};
   v2f vert(appdata_base v){v2f o;o.pos=UnityObjectToClipPos(v.vertex);o.normal=UnityObjectToWorldNormal(v.normal);o.view=WorldSpaceViewDir(v.vertex);return o;}
   fixed4 frag(v2f i):SV_Target {float f=pow(1-saturate(abs(dot(normalize(i.view),normalize(i.normal)))),4);return fixed4(_Color.rgb*.72,_Color.a*(.7+.55*f));}
   ENDCG
  }
 }
}
