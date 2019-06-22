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
//			Blend Off
			Blend SrcAlpha One
//			Blend SrcAlpha OneMinusSrcAlpha

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
				float3 color;
			};
			StructuredBuffer<Line> _LineBuffer;

            struct v2f
            {
                float3 uvw : TEXCOORD0;
				float4 color : TEXCOORD1;
//				float4 position : TEXCOORD1;
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

// TODO: LINESIZE could be per line...
#define LINESIZE 1

            v2f vert(uint vertexIndex : SV_VertexID, uint instanceIndex : SV_InstanceID)
            {
                v2f o;

				float lineIndex = floor((vertexIndex + 0.5f) / 6);
				float lineVertex = vertexIndex - lineIndex * 6;			// 0 - 5

				// we build a quad for each line
				// each quad is defined by 6 vertices (two triangles)
				// quadV.x = 0, 0, 1, 1, 1, 0
				// quadV.y = 0, 1, 1, 1, 0, 0
				float2 quadV = (float2)
					(frac((lineVertex.xx + float2(5.5f, 4.5f)) / 6.0f) > 0.5f);

				// two line end points
				float3 p0 = _LineBuffer[lineIndex].v0;
				float3 p1 = _LineBuffer[lineIndex].v1;

				// TODO: apply object -> world transform here!
				// could do instanced if necessary

				float3 color = _LineBuffer[lineIndex].color;
				float3 delta = p1 - p0;
				float deltaDist = length(delta);
				float3 deltaNormalized = delta / deltaDist;

				// construct the 4 corners of the quad we want to draw
				// we approximate the size of a pixel (not very well) in order to 
				// move the corners out from the line enough to encompass the desired width of the line
				float3 p0ToCamera = _WorldSpaceCameraPos - p0;
				float3 p1ToCamera = _WorldSpaceCameraPos - p1;
				float p0Dist = length(p0ToCamera);
				float p1Dist = length(p1ToCamera);

				float lineTweak = 0.001f;		// TODO: this value should be calculated based on target resolution
				float lineSize = lineTweak * (LINESIZE + 1);		// TODO: correct for edge-on projection
				float p0PixelSize = lineSize * p0Dist;
				float p1PixelSize = lineSize * p1Dist;

				float3 p0Perp = normalize(cross(delta, p0ToCamera)) * p0PixelSize;
				float3 p1Perp = normalize(cross(delta, p1ToCamera)) * p1PixelSize;

				// not quite correct because it doesn't take projection into account...
				// but close enough in most cases?
				// we're doing everything in 3D to try to retain the 3D depth info (if we want to clip against a depth buffer)
				// but we could instead project everything to a uniform depth in screenspace and all the lines would be perfect
				float3 v0 = p0 - deltaNormalized * p0PixelSize;
				float3 v1 = p1 + deltaNormalized * p1PixelSize;

				// these are the 4 corners
				float3 v0_0 = v0 - p0Perp;
				float3 v0_1 = v0 + p0Perp;
				float3 v1_0 = v1 - p1Perp;
				float3 v1_1 = v1 + p1Perp;

				// choose the corner based on quadV
				float3 vertexPositionWorld=
					lerp(
						lerp(v0_0, v0_1, quadV.y),
						lerp(v1_0, v1_1, quadV.y),
						quadV.x);
/*
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
*/

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

//				<------------------ quadV [0,1] ---------------->
//				<- p0PixelSize -><- deltaDist -><- p1PixelSize ->
//								 <-- u [0,1] -->
//				u(quadV) = 0,  quadV = p0PixelSize / total;
//				u(quadV) = 1,  quadV = (p0PixelSize + detalDist) / total;
//				u(quadV) = k * quadV + o;
//				0 = k * p0PixelSize / total + o
//				1 = k * (p0PixelSize + deltaDist) / total + o
//				1 = k * (p0PixelSize + deltaDist - p0PixelSize) / total
//				1 = k * deltaDist / total
//				total / deltaDist = k

				float total = deltaDist + p0PixelSize + p1PixelSize;
				float scale = total / deltaDist;
				float offset = -scale * p0PixelSize / total;

				// TODO: we could instead pass down the idealized UV coords in screenspace,
				// based on the projected line.. would give us better endcap results probably

				// uv.x is along the line, in world space, such that [0,1] represents exactly the [p0, p1] range
				// uv.y is perpendicular to the line, in screenspace.  [0,1] is across the geometry
				//		actual distance doesn't matter too much, just has to cover the relevant pixels, centered on 0.5 and be linearly varying in screenspace
				float2 uv;
				uv.x = quadV.x * scale + offset;
				uv.x *= o.vertex.w;
				uv.y = quadV.y * o.vertex.w;

				o.uvw = float3(uv, o.vertex.w);
				o.color = float4(color.rgb, 1.0f);

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

			float AA_threshold(
				float SDF,
				float threshold,
				float tweak,			// AA tweak value -- smaller values are blurrier, larger values are crisper, default depends on your SDF
				float2 continuous_UV)		// used to approximate local gradients, only works if the UVs are continuous
			{
				// compute AA scale, as a function of the local gradients
				float4 derivatives =
					float4(
						ddx(continuous_UV),
						ddy(continuous_UV)
					);

				float2 duv_length =
					float2(
						sqrt(dot(derivatives.xz, derivatives.xz)),
						sqrt(dot(derivatives.yw, derivatives.yw))
					);

				float scale = tweak / (duv_length.x + duv_length.y);

				return saturate(1.0f - scale * (SDF - threshold));
			}

			float Stripe(in float x, in float stripeX, in float pixelWidth)
			{
				// compute derivatives to get ddx / pixel
				float2 derivatives = float2(ddx(x), ddy(x));
				float derivLen = length(derivatives);
				float sharpen = 1.0f / max(derivLen, 0.00001f);
				return saturate(0.5f + 0.5f * (0.5f * pixelWidth - sharpen * abs(x - stripeX)));
			}

            float4 frag (v2f i) : SV_Target
            {
//                UNITY_SETUP_INSTANCE_ID(i); // necessary only if any instanced properties are going to be accessed in the fragment Shader.

                // sample the texture
//                fixed4 col = tex2D(_MainTex, i.uv) * UNITY_ACCESS_INSTANCED_PROP(Props, _Color);

//				float2 pixelPosition = i.position * _ScreenParams.xy;
//				float alpha = line_aa(pixelPosition, fx, fy, gx, gy, halfPixel, lineClamp);

				// reconstruct uv
				float2 uv;
				uv.x = i.uvw.x / i.uvw.z;
				uv.y = i.uvw.y / i.uvw.z;

				float alpha = Stripe(uv.y, 0.5f, LINESIZE);

				float endAlpha = AA_threshold(
					abs(uv.x - 0.5f),
					0.50f,
					1.0f,
					uv.xx);

				float4 col = float4(i.color.rgb, alpha * endAlpha);

				// apply fog
                // UNITY_APPLY_FOG(i.fogCoord, col);

//				col *= col;

                return col;
            }
            ENDCG
        }
    }
}
