Shader "Hidden/Underwater/DepthNormals"
{
	HLSLINCLUDE

	#define REQUIRE_DEPTH
	#include "../Libraries/URP.hlsl"
	#include "../Libraries/Common.hlsl"
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

	// Reconstruct view-space position from UV and depth.
	// p11_22 = (unity_CameraProjection._11, unity_CameraProjection._22)
	// p13_31 = (unity_CameraProjection._13, unity_CameraProjection._23)
	float3 ReconstructViewPos(float3 uvDepth, float2 p11_22, float2 p13_31)
	{
		return float3(((uvDepth.xy * 2.0 - 1.0 - p13_31) / p11_22) * CheckPerspective(uvDepth.z), uvDepth.z);
	}

	float4 AccurateReconstruction(float depth, float2 uv)
	{
		float2 delta = _ScreenParams.zw - 1.0;

		// Sample the neighbour fragments
		float2 lUV = float2(-delta.x, 0.0);
		float2 rUV = float2(delta.x, 0.0);
		float2 uUV = float2(0.0, delta.y);
		float2 dUV = float2(0.0, -delta.y);

		float3 c = float3(uv, 0.0); c.z = Linear01Depth(SampleSceneDepth(c.xy), _ZBufferParams); // Center
		float3 l1 = float3(uv + lUV, 0.0); l1.z = Linear01Depth(SampleSceneDepth(l1.xy), _ZBufferParams); // Left1
		float3 r1 = float3(uv + rUV, 0.0); r1.z = Linear01Depth(SampleSceneDepth(r1.xy), _ZBufferParams); // Right1
		float3 u1 = float3(uv + uUV, 0.0); u1.z = Linear01Depth(SampleSceneDepth(u1.xy), _ZBufferParams); // Up1
		float3 d1 = float3(uv + dUV, 0.0); d1.z = Linear01Depth(SampleSceneDepth(d1.xy), _ZBufferParams); // Down1

#if defined(_RECONSTRUCT_NORMAL_MEDIUM)
		uint closest_horizontal = l1.z > r1.z ? 0 : 1;
		uint closest_vertical = d1.z > u1.z ? 0 : 1;
#else
		float3 l2 = float3(uv + lUV * 2.0, 0.0); l2.z = Linear01Depth(SampleSceneDepth(l2.xy), _ZBufferParams); // Left2
		float3 r2 = float3(uv + rUV * 2.0, 0.0); r2.z = Linear01Depth(SampleSceneDepth(r2.xy), _ZBufferParams); // Right2
		float3 u2 = float3(uv + uUV * 2.0, 0.0); u2.z = Linear01Depth(SampleSceneDepth(u2.xy), _ZBufferParams); // Up2
		float3 d2 = float3(uv + dUV * 2.0, 0.0); d2.z = Linear01Depth(SampleSceneDepth(d2.xy), _ZBufferParams); // Down2

		const uint closest_horizontal = abs((2.0 * l1.z - l2.z) - c.z) < abs((2.0 * r1.z - r2.z) - c.z) ? 0 : 1;
		const uint closest_vertical = abs((2.0 * d1.z - d2.z) - c.z) < abs((2.0 * u1.z - u2.z) - c.z) ? 0 : 1;
#endif

		// Parameters used in coordinate conversion
		float3x3 camProj = (float3x3)unity_CameraProjection;
		float2 p11_22 = float2(camProj._11, camProj._22);
		float2 p13_31 = float2(camProj._13, camProj._23);

		// Calculate the triangle, in a counter-clockwize order, to
		// use based on the closest horizontal and vertical depths.
		// h == 0.0 && v == 0.0: p1 = left,  p2 = down
		// h == 1.0 && v == 0.0: p1 = down,  p2 = right
		// h == 1.0 && v == 1.0: p1 = right, p2 = up
		// h == 0.0 && v == 1.0: p1 = up,    p2 = left
		// Calculate the view space positions for the three points...
		float3 P0 = ReconstructViewPos(c, p11_22, p13_31);
		float3 P1;
		float3 P2;
		if (closest_vertical == 0)
		{
			P1 = ReconstructViewPos((closest_horizontal == 0 ? l1 : d1), p11_22, p13_31);
			P2 = ReconstructViewPos((closest_horizontal == 0 ? d1 : r1), p11_22, p13_31);
		}
		else
		{
			P1 = ReconstructViewPos((closest_horizontal == 0 ? u1 : r1), p11_22, p13_31);
			P2 = ReconstructViewPos((closest_horizontal == 0 ? l1 : u1), p11_22, p13_31);
		}

		// Use the cross product to calculate the normal...
		return float4(normalize(cross(P2 - P0, P1 - P0)), depth);
	}
	
	//Varyings/Attributes were removed in URP 10.0.0 so include an abstraction here for backwards compatibility
	struct Attributes
	{
		float4 positionOS 	: POSITION;
		float2 uv 			: TEXCOORD0;
		UNITY_VERTEX_INPUT_INSTANCE_ID
	};

	struct Varyings {
		float4 positionCS 		: POSITION;
		float2 uv 				: TEXCOORD0;
		UNITY_VERTEX_OUTPUT_STEREO
	};

	Varyings Vert(Attributes input)
	{
		Varyings output;

		UNITY_SETUP_INSTANCE_ID(input);
		UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

		output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
		output.uv.xy = input.uv;

		return output;
	}

	//https://github.com/Unity-Technologies/Graphics/blob/d7e4eb9266bd768669a016b1549b67489841f847/com.unity.render-pipelines.universal/ShaderLibrary/SSAO.hlsl
	float4 Frag(Varyings input) : SV_Target
	{
		UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

		float2 uv = UnityStereoTransformScreenSpaceTex(input.uv);
		float depth = Linear01Depth(SampleSceneDepth(uv), _ZBufferParams);

		return AccurateReconstruction(depth, uv);
	}
	ENDHLSL

	SubShader
	{
		Cull Off ZWrite Off ZTest Always

			Pass
		{
			Name "Depth Normals reconstruction"
			HLSLPROGRAM
			#pragma vertex Vert
			#pragma fragment Frag

			ENDHLSL
		}
	}
}