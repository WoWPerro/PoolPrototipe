//Stylized Water 2
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

float _DistortionFreq;
float _DistortionStrength;
float _DistortionSpeed;

//Victim of changes in early URP versions. Technically applies to 7.5.2 and older, but can't check for sub-versions
#if (SHADER_LIBRARY_VERSION_MAJOR == 7 && SHADER_LIBRARY_VERSION_MINOR < 5)
#define LEFT_HANDED_VIEW_SPACE
#endif

float3 GetWorldPosition(float4 screenPos, float deviceDepth )
{
	//This unrolls to an array using [unity_StereoEyeIndex] when VR is enabled
	float4x4 invViewProjMatrix = unity_CameraInvProjection;
	
	#if UNITY_REVERSED_Z //Anything other than OpenGL + Vulkan
	deviceDepth = (1.0 - deviceDepth) * 2.0 - 1.0;
	
	//https://issuetracker.unity3d.com/issues/shadergraph-inverse-view-projection-transformation-matrix-is-not-the-inverse-of-view-projection-transformation-matrix
	invViewProjMatrix._12_22_32_42 = -invViewProjMatrix._12_22_32_42;
	
	real rawDepth = deviceDepth;
	#else
	//Adjust z to match NDC for OpenGL + Vulkan
	real rawDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1, deviceDepth);
	#endif

	//Unrolled from ComputeWorldSpacePosition and ComputeViewSpacePosition functions. Since this is bugged between different URP versions
	float4 positionCS  = ComputeClipSpacePosition(screenPos.xy, rawDepth);
	float4 hpositionWS = mul(invViewProjMatrix, positionCS);
	
	//The view space uses a right-handed coordinate system.
	#ifndef LEFT_HANDED_VIEW_SPACE
	hpositionWS.z = -hpositionWS.z;
	#endif
	
	float3 positionVS = hpositionWS.xyz / max(0, hpositionWS.w);
	float3 positionWS = mul(unity_CameraToWorld, float4(positionVS, 1.0)).xyz;

	return positionWS;
}

TEXTURE2D(_DistortionNoise); SAMPLER(sampler_DistortionNoise);
TEXTURE2D(_DistortionSphere); SAMPLER(sampler_DistortionSphere);

#define HQ_WORLDSPACE_DISTORTION

#if SHADER_API_MOBILE
#undef HQ_WORLDSPACE_DISTORTION
#endif

float MapWorldSpaceDistortionOffsets(float3 wPos)
{
	wPos *= _DistortionFreq;
	float distortionOffset = _TimeParameters.x * _DistortionSpeed;
	
	float x1 =  SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, float2(wPos.y + distortionOffset, wPos.z + distortionOffset)).r * 2.0 - 1.0;
	#ifdef HQ_WORLDSPACE_DISTORTION
	float x2 =  SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, float2(wPos.y - distortionOffset * 0.5, wPos.z + distortionOffset)).r * 2.0 - 1.0;
	#endif

	//Note: okay to skip Y-axis projection
	
	float z1 =  SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, float2(wPos.x + distortionOffset, wPos.y + distortionOffset)).r * 2.0 - 1.0;
	#ifdef HQ_WORLDSPACE_DISTORTION
	float z2 =  SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, float2(wPos.x + distortionOffset * 0.5, wPos.y + distortionOffset)).r * 2.0 - 1.0;
	#endif

	#ifdef HQ_WORLDSPACE_DISTORTION
	return max(max(x1, x2), max(z1, z2));
	#else
	return max(x1, z1);
	#endif
}

void DistortUV(float2 uv, inout float2 distortedUV)
{
	float offset = 0;
	
#if _SCREENSPACE_DISTORTION
	float2 distortionFreq = uv * _DistortionFreq;
	float distortionOffset = _TimeParameters.x * _DistortionSpeed;
				
	float n1 = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, float2(distortionFreq.x + distortionOffset, distortionFreq.y + distortionOffset)).r;
	float n2 = SAMPLE_TEXTURE2D(_DistortionNoise, sampler_DistortionNoise, float2(distortionFreq.x - (distortionOffset * 0.5), distortionFreq.y)).r;

	offset = max(n1, n2) * 2.0 - 1.0;
#endif

#if _CAMERASPACE_DISTORTION
	offset = SAMPLE_TEXTURE2D(_DistortionSphere, sampler_DistortionSphere, uv).r;
#endif

#if _SCREENSPACE_DISTORTION || _CAMERASPACE_DISTORTION
	offset *= _DistortionStrength;

	#ifdef UNITY_REVERSED_Z
	//Offset always has to push up, otherwise creates a seam where the water meets the shore
	distortedUV = uv.xy - offset;
	#else
	distortedUV = uv.xy + offset;
	#endif
	
#endif
}