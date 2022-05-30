//Stylized Water 2
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

Shader "Hidden/StylizedWater2/UnderwaterPost"
{
	SubShader
	{
		Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
		LOD 100

		Pass
		{
			Name "Underwater Post Processing"
			ZTest Always
			ZWrite Off
			Cull Off

			HLSLPROGRAM
			
			#define VERTEX_PASS
			#pragma vertex Vertex
			#undef VERTEX_PASS
			#pragma fragment Fragment

			#pragma multi_compile_local _ BLUR
			#pragma multi_compile_local _ _SCREENSPACE_DISTORTION _CAMERASPACE_DISTORTION

			#include "../Libraries/URP.hlsl"
			#include "UnderwaterEffects.hlsl"
			#include "UnderwaterFog.hlsl"

			struct FullScreenAttributes
			{
			    float4 positionOS : POSITION;
			    float2 uv         : TEXCOORD0;
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
			TEXTURE2D(_UnderwaterMask); SAMPLER(sampler_UnderwaterMask);

			FullScreenVaryings Vertex(FullScreenAttributes input)
			{
				FullScreenVaryings output;

				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
	
			    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
			    output.uv.xy = input.uv;
				
				float4 projPos = output.positionCS * 0.5;
				projPos.xy = projPos.xy + projPos.w;
				output.uv.zw = projPos.xy;
				
				output.positionWS = TransformObjectToWorld(input.positionOS.xyz);

				return output;
			}

			#define BLUR_SAMPLES 8
			#define BLUR_QUALITY 8
			#define BLUR_RADIUS 4.0
			#define PI_2 6.28318530718
			
			float3 GaussianBlur(TEXTURE2D_X_PARAM(textureName, samplerTex), float2 uv)
			{
				float2 Radius = BLUR_RADIUS/_ScreenParams.xy;
		
				float3 color = 0;
				for(float d = 0; d < PI_2; d += PI_2/BLUR_SAMPLES)
				{
					for(float i= 1.0/BLUR_QUALITY; i <= 1.0; i += 1.0/BLUR_QUALITY)
					{
						color += SAMPLE_TEXTURE2D_X(textureName, samplerTex, uv + float2(cos(d) , sin(d)) * Radius * i).rgb;		
					}
				}
				color /= BLUR_QUALITY * BLUR_SAMPLES - (BLUR_SAMPLES- 1.0);

				return color;
			}

			half4 Fragment(FullScreenVaryings input) : SV_Target
			{
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

				//return float4(0,1,0,1);
				float2 uv = input.uv.xy;
				float2 uwUV = uv;
				
				DistortUV(uv, uwUV);
						
				float underwaterMask = SAMPLE_TEXTURE2D(_UnderwaterMask, sampler_UnderwaterMask, uwUV).r;
				uwUV = lerp(uv, uwUV, underwaterMask);
				//return float4(uwUV.xy, 0, 1);
				
				half4 screenColor = SAMPLE_TEXTURE2D_X(_SourceTex, sampler_SourceTex, uwUV);
				
				float3 farColor = screenColor.rgb;
				float waterDensity = 1.0;
				
#if BLUR
				farColor = GaussianBlur(_SourceTex, sampler_SourceTex, uwUV);			

				float sceneDepth = SampleSceneDepth(uwUV);
				float3 positionWS = GetWorldPosition(float4(uwUV.xy, input.uv.zw), sceneDepth);

				float distanceDensity = ComputeDistanceXYZ(positionWS);	
				float heightDensity = ComputeHeight(positionWS);
				waterDensity = ComputeDensity(distanceDensity, heightDensity);
#endif

				float3 finalColor = lerp(screenColor.rgb, farColor.rgb, underwaterMask * waterDensity);
				
				return float4(finalColor.rgb, screenColor.a);
			}

			ENDHLSL
		}
	}
}
