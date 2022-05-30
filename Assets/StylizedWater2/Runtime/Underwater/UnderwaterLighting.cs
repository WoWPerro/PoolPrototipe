//Stylized Water 2: Underwater Rendering extension
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.Universal.Internal;

namespace StylizedWater2
{
    public static class UnderwaterLighting
    {
#if URP
        private static int _AmbientParams = Shader.PropertyToID("_AmbientParams");
        private static int _UnderwaterAmbientColor = Shader.PropertyToID("_UnderwaterAmbientColor");
        private static int _MainLightColorUnderwater = Shader.PropertyToID("_MainLightColorUnderwater");
        private static int _MainLightDir = Shader.PropertyToID("_MainLightDir");
        
        //Global values that needs to be set up again, won't survive opaque pass
        private static int skyboxCubemap = Shader.PropertyToID("skyboxCubemap");
        private static int skyboxCubemap_HDR = Shader.PropertyToID("skyboxCubemap_HDR");
        private static int unity_WorldToLight = Shader.PropertyToID("unity_WorldToLight");

        public static void PassAmbientLighting(ScriptableRenderPass pass, CommandBuffer cmd)
        {
            if (RenderSettings.ambientMode == AmbientMode.Skybox)
            {
                //Normally set up on a per-renderer basis, emulate the behaviour for post-processing passes
                cmd.SetGlobalTexture(skyboxCubemap, ReflectionProbe.defaultTexture);
                cmd.SetGlobalVector(skyboxCubemap_HDR, ReflectionProbe.defaultTextureHDRDecodeValues);
            }
            
            cmd.SetGlobalVector(_AmbientParams, new Vector4(Mathf.GammaToLinearSpace(RenderSettings.ambientIntensity), RenderSettings.ambientMode == AmbientMode.Skybox ? 1 : 0, 0, 0));
            //URP uses spherical harmonics to store the ambient light color, even if it's flat. But this is done in native engine code
            cmd.SetGlobalColor(_UnderwaterAmbientColor, RenderSettings.ambientMode == AmbientMode.Flat ? RenderSettings.ambientLight.linear : RenderSettings.ambientEquatorColor.linear);
        }
        
        //Post processing isn't a renderer, attempt to reproduce the lighting setup.
        //Potentially possible to completely reverse engineer the ForwardLights pass, but it too complex and prone to breaking in URP updates
        public static void PassMainLight(CommandBuffer cmd, RenderingData renderingData)
        {
            // When no lights are visible, main light will be set to -1.
            if (renderingData.lightData.mainLightIndex > -1)
            {
                VisibleLight mainLight = renderingData.lightData.visibleLights[renderingData.lightData.mainLightIndex];
    
                if (mainLight.lightType == LightType.Directional)
                {
                    cmd.SetGlobalMatrix(unity_WorldToLight, mainLight.light.transform.worldToLocalMatrix);
                    
                    //For normal renderers, the color is black if the light is disabled: emulate this behaviour.
                    cmd.SetGlobalColor(_MainLightColorUnderwater, mainLight.light.gameObject.activeInHierarchy ? mainLight.light.color.linear * mainLight.light.intensity : Color.clear);
                    
                    //cmd.SetGlobalVector(_MainLightDir, -mainLight.light.transform.forward);
                    //Dir can be derived from 2nd column of matrix
                    cmd.SetGlobalVector(_MainLightDir, -mainLight.localToWorldMatrix.GetColumn(2));
                }
            }
            else
            {
                cmd.SetGlobalColor(_MainLightColorUnderwater, Color.clear);
            }
        }
        
        public static class DepthNormals
        {
            private static RenderTextureDescriptor depthNormalDsc;
            private static readonly int depthNormalsID = Shader.PropertyToID("_CameraDepthNormalsTexture"); //Use legacy name, as not to stomp over the depth normals pre-pass
            private static Material depthNormalsMat;
            
            public static void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor, UnderwaterResources resources)
            {
                //https://github.com/Unity-Technologies/Graphics/blob/c6eb37bbad8d85f5c6f9aa53648d2f4a49c33b59/com.unity.render-pipelines.universal/Runtime/Passes/DepthNormalOnlyPass.cs#L40
                depthNormalDsc = cameraTextureDescriptor;
                depthNormalDsc.depthBufferBits = 0;
                depthNormalDsc.colorFormat = RenderTextureFormat.RGHalf;
                depthNormalDsc.msaaSamples = 1;
            
                cmd.GetTemporaryRT(depthNormalsID, depthNormalDsc);
                cmd.SetGlobalTexture(depthNormalsID, depthNormalsID);
                
                if(!depthNormalsMat) depthNormalsMat = CoreUtils.CreateEngineMaterial(resources.depthNormalsShader);
            }

            public static void Generate(ScriptableRenderPass pass, CommandBuffer cmd, RenderingData renderingData)
            {
                pass.Blit(cmd, pass.depthAttachment /* not actually used */, depthNormalsID, depthNormalsMat, 0);
            }

            public static void Cleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(depthNormalsID);
            }
        }
#endif
    }
}