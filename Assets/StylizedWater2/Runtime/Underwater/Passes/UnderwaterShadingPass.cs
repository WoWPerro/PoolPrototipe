//Stylized Water 2: Underwater Rendering extension
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

using UnityEngine;
using UnityEngine.Rendering;
#if URP
using UnityEngine.Rendering.Universal;

namespace StylizedWater2
{
    class UnderwaterShadingPass : ScriptableRenderPass
    {
        private const string ProfilerTag = "Underwater Rendering: Shading";
        private static readonly ProfilingSampler m_ProfilingSampler = new ProfilingSampler(ProfilerTag);

        private Material Material;
        private UnderwaterRenderFeature.Settings settings;
        private UnderwaterResources resources;
        private UnderwaterRenderFeature renderFeature;

        private bool reconstructSceneNormals;

        public UnderwaterShadingPass(UnderwaterRenderFeature renderFeature)
        {
            this.renderFeature = renderFeature;
            this.settings = renderFeature.settings;
            this.resources = renderFeature.resources;
            Material = UnderwaterRenderFeature.CreateMaterial(ProfilerTag, renderFeature.resources.underwaterShader);
        }

        private RenderTargetHandle mainTexHandle;
        private int mainTexID = Shader.PropertyToID("_SourceTex");
        private RenderTargetIdentifier cameraColorTarget;
        
        public const string DEPTH_NORMALS_KEYWORD = "_REQUIRE_DEPTH_NORMALS";
        public const string SOURCE_DEPTH_NORMALS_KEYWORD = "_SOURCE_DEPTH_NORMALS";
        
        public void Setup(ScriptableRenderer renderer)
        {
            #if URP_10_0_OR_NEWER
            ConfigureInput(ScriptableRenderPassInput.Depth);
            #endif
            
            if (settings.directionalCaustics)
            {
                #if URP_10_0_OR_NEWER
                if(settings.accurateDirectionalCaustics) 
                {
                    ConfigureInput(ScriptableRenderPassInput.Normal);
                    reconstructSceneNormals = false;
                }
                CoreUtils.SetKeyword(Material, SOURCE_DEPTH_NORMALS_KEYWORD, settings.accurateDirectionalCaustics);
                #else
                reconstructSceneNormals = true;
                CoreUtils.SetKeyword(Material, SOURCE_DEPTH_NORMALS_KEYWORD, false);
                #endif
            }
            
            CoreUtils.SetKeyword(Material, DEPTH_NORMALS_KEYWORD, settings.directionalCaustics);
            CoreUtils.SetKeyword(Material, UnderwaterRenderer.TRANSLUCENCY_KEYWORD, renderFeature.keywordStates.translucency);
            CoreUtils.SetKeyword(Material, UnderwaterRenderer.CAUSTICS_KEYWORD, renderFeature.keywordStates.caustics);
            
            #if !URP_10_0_OR_NEWER
            //otherwise fetched in Execute function, no longer allowed from a ScriptableRenderFeature setup function (target may be not be created yet, or was disposed)
            this.cameraColorTarget = renderer.cameraColorTarget;
            #endif
        }
        
#if URP_9_0_OR_NEWER
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
#else
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
#endif
        {
            #if URP_9_0_OR_NEWER
            RenderTextureDescriptor cameraTextureDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            #endif
            
            ConfigurePass(cmd, cameraTextureDescriptor);
        }

        public void ConfigurePass(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            mainTexHandle.id = mainTexID;

            cmd.GetTemporaryRT(mainTexHandle.id, cameraTextureDescriptor);
            cmd.SetGlobalTexture(mainTexHandle.id, mainTexID);
            
            if(reconstructSceneNormals) UnderwaterLighting.DepthNormals.Configure(cmd, cameraTextureDescriptor, this.resources);
        }
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                #if URP_10_0_OR_NEWER
                //Color target can now only be fetched inside a ScriptableRenderPass
                this.cameraColorTarget = renderingData.cameraData.renderer.cameraColorTarget;
                #endif

                UnderwaterLighting.PassAmbientLighting(this, cmd);
                UnderwaterLighting.PassMainLight(cmd, renderingData);
                
                if(reconstructSceneNormals) UnderwaterLighting.DepthNormals.Generate(this, cmd, renderingData);

                #if URP_12_0_OR_NEWER //No longer required color target copy, blit directly
                cmd.SetGlobalTexture(mainTexHandle.id, cameraColorTarget);
                this.Blit(cmd, ref renderingData, Material, 0);
                #else
                //Color copy
                Blit(cmd, cameraColorTarget, mainTexHandle.id);
                
                cmd.SetGlobalTexture(mainTexHandle.id, mainTexHandle.id);
                Blit(cmd, mainTexHandle.id, cameraColorTarget, Material, 0);
                #endif
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

#if URP_9_0_OR_NEWER
        public override void OnCameraCleanup(CommandBuffer cmd)
#else
        public override void FrameCleanup(CommandBuffer cmd)
#endif
        {
            cmd.ReleaseTemporaryRT(mainTexID);
            if(reconstructSceneNormals) UnderwaterLighting.DepthNormals.Cleanup(cmd);
            
            //UnderwaterLighting.Clear();
        }
    }

}
#endif