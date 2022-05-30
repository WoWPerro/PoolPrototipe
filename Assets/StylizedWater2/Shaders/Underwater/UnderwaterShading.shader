//Stylized Water 2
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

Shader "Hidden/StylizedWater2/Underwater"
{
	SubShader
	{
		Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
		LOD 100

		Pass
		{
			Name "Underwater Shading"
			ZTest Always
			ZWrite Off
			Cull Off

			HLSLPROGRAM
			
			#define VERTEX_PASS
			#pragma vertex Vertex
			#undef VERTEX_PASS
			#pragma fragment Fragment
			#pragma multi_compile_local_fragment _ _REQUIRE_DEPTH_NORMALS
			#pragma multi_compile_local_fragment _ _SOURCE_DEPTH_NORMALS
			#pragma multi_compile_local_fragment _ _TRANSLUCENCY
			#pragma multi_compile_local_fragment _ _CAUSTICS
			
			//#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE

			#define _ADVANCED_SHADING 1
			#define UNDERWATER_ENABLED 1

			#include "../Libraries/URP.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
			
			#include "../Libraries/Common.hlsl"
			#include "../Libraries/Input.hlsl"
			#include "../Libraries/Caustics.hlsl"
			#include "../Underwater/UnderwaterFog.hlsl"
			#include "../Underwater/UnderwaterShading.hlsl"
			#include "../Libraries/Waves.hlsl"
			#include "../Libraries/Lighting.hlsl"
			#include "UnderwaterEffects.hlsl"

			#if _SOURCE_DEPTH_NORMALS && SHADER_LIBRARY_VERSION_MAJOR >= 10
            #define DEPTH_NORMALS_PREPASS_AVAILABLE
            #else
            #undef DEPTH_NORMALS_PREPASS_AVAILABLE
            #endif
			
			#if _REQUIRE_DEPTH_NORMALS
			#ifndef DEPTH_NORMALS_PREPASS_AVAILABLE
			TEXTURE2D(_CameraDepthNormalsTexture); SAMPLER(sampler_CameraDepthNormalsTexture);
			#else
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
			#endif
			float3 SampleDepthNormals(float2 uv)
			{
				#ifdef DEPTH_NORMALS_PREPASS_AVAILABLE
				return half3(SampleSceneNormals(uv));
				#else
				return SAMPLE_TEXTURE2D(_CameraDepthNormalsTexture, sampler_CameraDepthNormalsTexture, uv).rgb;
				#endif
			}
			#endif

			float4x4 unity_WorldToLight;
			float _UnderwaterCausticsStrength;

			float4 _TestPosition;

			struct FullScreenAttributes
			{
				float3 positionOS   : POSITION;
				float2 uv           : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct FullScreenVaryings
			{
				half4 positionCS    : SV_POSITION;
				half3 positionWS    : TEXCOORD2;
				half4 uv            : TEXCOORD0;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			TEXTURE2D_X(_SourceTex); SAMPLER(sampler_SourceTex); float4 _SourceTex_TexelSize;

			FullScreenVaryings Vertex(FullScreenAttributes input)
			{
				FullScreenVaryings output;

				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
				
				output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
				output.uv.xy = UnityStereoTransformScreenSpaceTex(input.uv);
				output.uv.zw = ComputeScreenPos(output.positionCS.xyzw).xy;
				
				output.positionWS = TransformObjectToWorld(input.positionOS);

				return output;
			}

			float SampleShadows(float3 positionWS)
			{
			    //Fetch shadow coordinates for cascade.
			    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
				float attenuation = MainLightRealtimeShadow(shadowCoord);
			
				return attenuation; 
			}
			
			half4 Fragment(FullScreenVaryings input) : SV_Target
			{
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

				float2 uv = input.uv.xy;
				float4 screenPos = float4(uv.xy, input.uv.zw);
				half4 screenColor = SAMPLE_TEXTURE2D_X(_SourceTex, sampler_SourceTex, uv);
				
				float sceneDepth = SampleSceneDepth(uv);
				float3 worldPos = GetWorldPosition(screenPos, sceneDepth);
				//Test if world position actually corresponds to world units
				//float dist = 1-saturate(length(worldPos - _TestPosition.xyz) / _TestPosition.w);
				//return float4((dist.xxx), 1);		
				//return float4(frac(worldPos), 1);
				
				float skyboxMask = Linear01Depth(sceneDepth, _ZBufferParams) > 0.99 ? 1 : 0;
				//return float4(skyboxMask.rrr, 1);
			
				float underwaterMask = SAMPLE_TEXTURE2D(_UnderwaterMask, sampler_UnderwaterMask, uv).r;
			
				float sceneMask = saturate(underwaterMask) * 1-skyboxMask;

				//Water density gradients
				float distanceDensity = ComputeDistanceXYZ(worldPos);
				float heightDensity = ComputeHeight(worldPos) * sceneMask;
				float waterDensity = ComputeDensity(distanceDensity, heightDensity);
				waterDensity *= underwaterMask;
				//return float4(waterDensity.xxx, 1);	

				float shadowMask = 1;
				#if _CAUSTICS && _ADVANCED_SHADING && !SHADER_API_GLES3
				shadowMask = SampleShadows(worldPos);
				//shadowMask = lerp(shadowMask, 1.0, waterDensity); //Not needed atm
				//return float4(shadowMask.xxx, 1.0);
				#endif

#if _CAUSTICS				
				float2 projection = worldPos.xz;
				#if _REQUIRE_DEPTH_NORMALS
				//Project from directional light. No great, projection rotates around the light's position just like a cookie
				float3 lightProj = mul((float4x4)unity_WorldToLight, float4(worldPos, 1.0)).xyz;
				projection = lightProj.xy;
				#endif

				float3 caustics = SampleCaustics(projection, _TimeParameters.x * _CausticsSpeed, _CausticsTiling) * _CausticsBrightness;
				caustics *= saturate(sceneMask * (1-waterDensity) * underwaterMask) * length(_MainLightColorUnderwater.rgb) * shadowMask;
				caustics *= _UnderwaterCausticsStrength;
				//Use depth normals in URP 10 for angle masking
#if _REQUIRE_DEPTH_NORMALS
				float3 viewNormal = SampleDepthNormals(uv) * 2.0 - 1.0;
				float3 worldNormal = normalize(mul((float3x3)unity_MatrixInvV , viewNormal).xyz);
				//return float4(saturate(worldNormal), 1.0);

				float NdotL = saturate(dot(worldNormal, _MainLightDir.xyz));
				
				caustics *= NdotL;
#endif
				
#if _ADVANCED_SHADING
				//Fade the effect out as the sun approaches the horizon (80 to 90 degrees)
				half sunAngle = saturate(dot(float3(0, 1, 0), _MainLightDir));
				half angleMask = saturate(sunAngle * 10); /* 1.0/0.10 = 10 */
				caustics *= angleMask;
#endif

				screenColor.rgb += caustics;
#endif
				
				float3 waterColor = GetUnderwaterFogColor(_WaterShallowColor.rgb, _WaterDeepColor.rgb, distanceDensity, heightDensity);

				float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - worldPos);
				
				//Not using the real shadow mask, since shadows on geometry are already lit
				ApplyUnderwaterLighting(waterColor, 1.0, float3(0,1,0), viewDir);

				#if _TRANSLUCENCY
				TranslucencyData translucencyData = PopulateTranslucencyData(_WaterShallowColor.rgb, _MainLightDir,  _MainLightColorUnderwater.rgb, viewDir, float3(0,1,0), float3(0,1,0), 0, _TranslucencyParams);
				translucencyData.strength *= _UnderwaterFogBrightness * _UnderwaterSubsurfaceStrength * sceneMask * (1-heightDensity);
				ApplyTranslucency(translucencyData, waterColor);
				#endif

				screenColor.rgb = lerp(screenColor.rgb, waterColor.rgb, waterDensity);

				return screenColor;
			}

			ENDHLSL
		}
	}
}