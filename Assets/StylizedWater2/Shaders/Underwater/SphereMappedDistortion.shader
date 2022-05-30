Shader "Hidden/StylizedWater2/SphereMappedDistortionOffset"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        ZTest Always
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "../Libraries/URP.hlsl" //Required to find DecodeHDREnvironment down the line
            #include "UnderwaterEffects.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float3 positionOS : TEXCOORD2;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;
                
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionOS = v.positionOS.xyz;
                
                return o;
            }

            float4 frag (Varyings input) : SV_Target
            {
                return float4(MapWorldSpaceDistortionOffsets(input.positionOS).xxx, 1.0);
            }
            ENDHLSL
        }
    }
}
