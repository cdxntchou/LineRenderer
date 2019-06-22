Shader "Unlit/UnlitLineShader2"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		_Color("Color", Color) = (1,1,1,1)
		_CoordX("CoordX", Color) = (0, 0, 1, 1)
		_CoordY("CoordY", Color) = (0, 1, 0, 1)
	}
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
			Cull Off
			ZTest Always
			ZWrite Off
			Blend Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // make fog work
//            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            struct s_vs_in
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
				float2 uv2 : TEXCOORD1;
				UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
				float4 position : TEXCOORD1;
				float4 color : TEXCOORD2;
				// UNITY_FOG_COORDS(2)
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID // necessary only if you want to access instanced properties in fragment Shader.
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

//			float4 _PositionTransform;

			UNITY_INSTANCING_BUFFER_START(Props)
				UNITY_DEFINE_INSTANCED_PROP(float4, _Color)
				UNITY_DEFINE_INSTANCED_PROP(float4, _CoordX)
				UNITY_DEFINE_INSTANCED_PROP(float4, _CoordY)
				UNITY_DEFINE_INSTANCED_PROP(float4, _Fx)
				UNITY_DEFINE_INSTANCED_PROP(float4, _Fy)
				UNITY_DEFINE_INSTANCED_PROP(float4, _Gx)
				UNITY_DEFINE_INSTANCED_PROP(float4, _Gy)
				UNITY_DEFINE_INSTANCED_PROP(float4, _HalfPixel)
				UNITY_DEFINE_INSTANCED_PROP(float4, _LineClamp)
			UNITY_INSTANCING_BUFFER_END(Props)

            v2f vert (s_vs_in v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o); // necessary only if you want to access instanced properties in the fragment Shader.

				float4 coordX= UNITY_ACCESS_INSTANCED_PROP(Props, _CoordX);
				float4 coordY= UNITY_ACCESS_INSTANCED_PROP(Props, _CoordY);

				float cornerIndex = v.uv2.x;

				float4 cornerMask = (cornerIndex == float4(0.0f, 1.0f, 2.0f, 3.0f));	// select mask
				float2 transformedCoords;
				transformedCoords.x = dot(cornerMask, coordX);
				transformedCoords.y = dot(cornerMask, coordY);

				// convert to position, etc.
//				o.vertex.xy = transformedCoords * _PositionTransform.xy + _PositionTransform.zw;
				o.vertex.xy = transformedCoords * float2(2.0f, -2.0f) / _ScreenParams.xy + float2(-1.0f, 1.0f);
				o.vertex.zw = 1.0f;

//				o.vertex = UnityObjectToClipPos(v.vertex.xyz);

				o.position = ComputeScreenPos(o.vertex);

                o.uv = v.uv;
				o.color = float4(cornerMask.xyz, 1.0f);

				// UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

			float line_aa(in float2 pixelPosition, float3 Fx, float3 Fy, float3 Gx, float3 Gy, float2 halfPixel, float4 lineClamp)
			{
				float2	l0;
				l0.x = dot(pixelPosition.xy, Fx.xy) + Fx.z;
				l0.y = dot(pixelPosition.xy, Fy.xy) + Fy.z;

				float2 l1;
				l1.x = dot(pixelPosition.xy, Gx.xy) + Gx.z;
				l1.y = dot(pixelPosition.xy, Gy.xy) + Gy.z;

				float2 pos = max(l0.xy, l1.xy) + halfPixel.xy;
				float2 neg = min(l0.xy, l1.xy) - halfPixel.xy;

				float2 cpos = min(pos, lineClamp.yw);
				float2 cneg = max(neg, lineClamp.xz);

				float overlap_x = saturate(saturate(cpos.x - cneg.x) / abs(pos.x - neg.x));
				float overlap_y = saturate(saturate(cpos.y - cneg.y) / abs(pos.y - neg.y));

				return overlap_x * overlap_y;
			}

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i); // necessary only if any instanced properties are going to be accessed in the fragment Shader.

                // sample the texture
//                fixed4 col = tex2D(_MainTex, i.uv) * UNITY_ACCESS_INSTANCED_PROP(Props, _Color);

				float3 fx = UNITY_ACCESS_INSTANCED_PROP(Props, _Fx);
				float3 fy = UNITY_ACCESS_INSTANCED_PROP(Props, _Fy);
				float3 gx = UNITY_ACCESS_INSTANCED_PROP(Props, _Gx);
				float3 gy = UNITY_ACCESS_INSTANCED_PROP(Props, _Gy);
				float2 halfPixel = UNITY_ACCESS_INSTANCED_PROP(Props, _HalfPixel);
				float4 lineClamp = UNITY_ACCESS_INSTANCED_PROP(Props, _LineClamp);

				float2 pixelPosition = i.position * _ScreenParams.xy;
				float alpha = line_aa(pixelPosition, fx, fy, gx, gy, halfPixel, lineClamp);

				float4 col = float4(alpha.xxx, 1.0f); // i.position;

				// apply fog
                // UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
