//Stylized Water 2: Underwater Rendering extension
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
#if URP
using UnityEngine.Rendering.Universal;

namespace StylizedWater2
{
    public class UnderwaterMaskPass : ScriptableRenderPass
    {
        private const string ProfilerTag = "Underwater Rendering: Mask";
        private static ProfilingSampler m_ProfilingSampler = new ProfilingSampler(ProfilerTag);
        private static Mesh underwaterMaskMesh;

        private Material Material;

        private int waterMaskID = Shader.PropertyToID("_UnderwaterMask");

        private UnderwaterRenderFeature renderFeature;

        public UnderwaterMaskPass(UnderwaterRenderFeature renderFeature)
        {
            this.renderFeature = renderFeature;
            Material = UnderwaterRenderFeature.CreateMaterial(ProfilerTag, renderFeature.resources.watermaskShader);
        }

        public void Setup()
        {
            if (!underwaterMaskMesh) underwaterMaskMesh = UnderwaterUtilities.CreateMaskMesh();

            CoreUtils.SetKeyword(Material, UnderwaterRenderer.WAVES_KEYWORD, renderFeature.keywordStates.waves);

            ConfigureTarget(waterMaskID);
            ConfigureClear(ClearFlag.All, Color.clear);
        }
        
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            cameraTextureDescriptor.width /= 4;
            cameraTextureDescriptor.height /= 4;
            cameraTextureDescriptor.msaaSamples = 1;
            cameraTextureDescriptor.graphicsFormat = GraphicsFormat.R8_UNorm;
            cmd.GetTemporaryRT(waterMaskID, cameraTextureDescriptor, FilterMode.Bilinear);
            
            cmd.SetGlobalTexture(waterMaskID, waterMaskID);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                cmd.DrawMesh(underwaterMaskMesh, Matrix4x4.identity, Material, 0);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void FrameCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(waterMaskID);
        }
    }
}
#endif