Shader "Unlit/UnlitLineShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		_Color("Color", Color) = (1,1,1,1)
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
			#pragma target 5.0
			#pragma vertex vert
            #pragma fragment frag
            
            // make fog work
//            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

			// this struct should match the memory layout of LineRendererProxy.Line
			struct Line
			{
				float3 v0;
				float3 v1;
			};
			StructuredBuffer<Line> _LineBuffer;

            struct v2f
            {
//                float2 uv : TEXCOORD0;
//				float4 position : TEXCOORD1;
				float4 color : TEXCOORD2;
				// UNITY_FOG_COORDS(2)
                float4 vertex : SV_POSITION;
//                UNITY_VERTEX_INPUT_INSTANCE_ID // necessary only if you want to access instanced properties in fragment Shader.
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


            v2f vert(uint vertexIndex : SV_VertexID, uint instanceIndex : SV_InstanceID)
            {
                v2f o;

				float lineIndex = floor((vertexIndex + 0.5f) / 6);
				float lineVertex = vertexIndex - lineIndex * 6;			// 0 - 5

				// each quad is defined by 6 vertices (two triangles):
				// quadV.x = 0, 0, 1, 1, 1, 0
				// quadV.y = 0, 1, 1, 1, 0, 0
				float2 quadV = (float2)
					(frac((lineVertex.xx + float2(5.5f, 4.5f)) / 6.0f) > 0.5f);

				// two line end points
				float3 p0 = _LineBuffer[lineIndex].v0;
				float3 p1 = _LineBuffer[lineIndex].v1;
				float3 delta = p1 - p0;

				float3 p0ToCamera = _WorldSpaceCameraPos - p0;
				float3 p1ToCamera = _WorldSpaceCameraPos - p1;
				float p0Dist = length(p0ToCamera);
				float p1Dist = length(p1ToCamera);

				float p0PixelSize = 0.004f * p0Dist; // / p0Dist;
				float p1PixelSize = 0.004f * p1Dist; // / p1Dist;

				float3 p0Perp = normalize(cross(delta, p0ToCamera)) * p0PixelSize;
				float3 p1Perp = normalize(cross(delta, p1ToCamera)) * p1PixelSize;

				// not quite correct because it doesn't take projection into account...
				// but close enough in most cases?
				float3 v0 = p0 - normalize(delta) * p0PixelSize;
				float3 v1 = p1 + normalize(delta) * p1PixelSize;

				float3 v0_0 = v0 - p0Perp;
				float3 v0_1 = v0 + p0Perp;

				float3 v1_0 = v1 - p1Perp;
				float3 v1_1 = v1 + p1Perp;

				float3 vertexPositionWorld=
					lerp(
						lerp(v0_0, v0_1, quadV.y),
						lerp(v1_0, v1_1, quadV.y),
						quadV.x);

				// find orthogonal transform, mapping (0,0) -> p0, and (1,0) -> p1
				// F(p).x=	p.x * fx.x + p.y * fx.y + fx.z
				// F(p).y=	p.x * fy.x + p.y * fy.y + fx.z
				float3 fx;
				fx.x = delta.x;
				fx.y = delta.y;
				fx.z = p0.x;

				float3 fy;
				fy.x = delta.y;
				fy.y = -delta.x;
				fy.z = p0.y;

				// invert matrix:		mapping (p0_t0) -> (0, 0)  and (p1_t0) -> (1, 0)
				float length2 = dot(delta, delta);
				float3 ifx, ify;
				ifx.x = fx.x / length2;
				ifx.y = fy.x / length2;
				ifx.z = (-fx.z * ifx.x) + (-fy.z * ifx.y);
				ify.x = fx.y / length2;
				ify.y = fy.y / length2;
				ify.z = (-fx.z * ify.x) + (-fy.z * ify.y);

				// todo: can we setup instance id properly here?
//                UNITY_SETUP_INSTANCE_ID(v);
//                UNITY_TRANSFER_INSTANCE_ID(v, o); // necessary only if you want to access instanced properties in the fragment Shader.

				// convert to position, etc.
//				o.vertex.xy = transformedCoords * _PositionTransform.xy + _PositionTransform.zw;

//				o.vertex.xy = transformedCoords * float2(2.0f, -2.0f) / _ScreenParams.xy + float2(-1.0f, 1.0f);
//				o.vertex.zw = 1.0f;

//				o.vertex = UnityObjectToClipPos(vertexPosition.xyz);
				o.vertex = mul(UNITY_MATRIX_VP, float4(vertexPositionWorld.xyz, 1.0));

//				o.position = ComputeScreenPos(o.vertex);

//              o.uv = v.uv;
				o.color = float4(1.0f, 1.0f, 1.0f, 1.0f);

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
//                UNITY_SETUP_INSTANCE_ID(i); // necessary only if any instanced properties are going to be accessed in the fragment Shader.

                // sample the texture
//                fixed4 col = tex2D(_MainTex, i.uv) * UNITY_ACCESS_INSTANCED_PROP(Props, _Color);

//				float2 pixelPosition = i.position * _ScreenParams.xy;
//				float alpha = line_aa(pixelPosition, fx, fy, gx, gy, halfPixel, lineClamp);

				float4 col = i.color;

				// apply fog
                // UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
