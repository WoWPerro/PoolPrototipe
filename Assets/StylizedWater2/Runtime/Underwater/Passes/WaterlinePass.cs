//Stylized Water 2: Underwater Rendering extension
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

using UnityEngine;
using UnityEngine.Rendering;
#if URP
using UnityEngine.Rendering.Universal;

namespace StylizedWater2
{
    public class UnderwaterLinePass : ScriptableRenderPass
    {
        private const string ProfilerTag = "Underwater line Rendering";
        private static int _WaterLineWidth = Shader.PropertyToID("_WaterLineWidth");
        private static Mesh mesh;
        private UnderwaterRenderFeature.Settings settings;

        private UnderwaterRenderFeature renderFeature;
        
        private Material Material;
        
        public const string REFRACTION_KEYWORD = "_REFRACTION";

        public UnderwaterLinePass(UnderwaterRenderFeature renderFeature)
        {
            this.renderFeature = renderFeature;
            this.settings = renderFeature.settings;
            Material = UnderwaterRenderFeature.CreateMaterial(ProfilerTag, renderFeature.resources.waterlineShader);
        }

        public void Setup()
        {
            if (!mesh) mesh = UnderwaterUtilities.CreateMaskMesh();
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            ConfigureClear(ClearFlag.None, Color.clear);
            
            CoreUtils.SetKeyword(Material, REFRACTION_KEYWORD, settings.waterlineRefraction);
            CoreUtils.SetKeyword(Material, UnderwaterRenderer.TRANSLUCENCY_KEYWORD, renderFeature.keywordStates.translucency);
            CoreUtils.SetKeyword(Material, UnderwaterRenderer.WAVES_KEYWORD, renderFeature.keywordStates.waves);
        }
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get(ProfilerTag);
            
            UnderwaterLighting.PassAmbientLighting(this, cmd);
            UnderwaterLighting.PassMainLight(cmd, renderingData);
            
            Material.SetFloat(_WaterLineWidth, UnderwaterRenderer.Instance.waterLineThickness * 0.1f);
            cmd.DrawMesh(mesh, Matrix4x4.identity, Material, 0, 0);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
#endif