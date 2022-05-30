//Stylized Water 2
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

Shader "Hidden/StylizedWater2/UnderwaterMask"
{
	SubShader
	{
		Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

		//ZWrite should be disabled for post-processing pass
		Cull Off ZWrite On

	   Pass
	   {
		   Name "Underwater Mask"
		   HLSLPROGRAM
		   #pragma prefer_hlslcc gles
		   #pragma exclude_renderers d3d11_9x

		   #pragma vertex VertexWaterLine
		   #pragma fragment frag

		   #define VERTEX_PASS //Bypasses normal calculations for waves
		   #define FULLSCREEN_QUAD

		   #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		   #include "UnderwaterMask.hlsl"

		   #pragma multi_compile_local _ _WAVES

		   half4 frag(Varyings input) : SV_Target
		   {
		   		UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

		   		//Perform some antialiasing so the target can be rendered at much lower resolution
		   		float gradient = pow(abs(input.uv.y), 256);
				return 1-gradient;
		   }
		   ENDHLSL
		}
	}
	FallBack "Hidden/InternalErrorShader"
}