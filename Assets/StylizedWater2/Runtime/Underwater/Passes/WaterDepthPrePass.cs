//Stylized Water 2: Underwater Rendering extension
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

using UnityEngine;
using UnityEngine.Rendering;
#if URP
using UnityEngine.Rendering.Universal;

namespace StylizedWater2
{
    class WaterDepthPrePass : ScriptableRenderPass
    {
        private const string ProfilerTag = "Underwater rendering: Water depth Pre-pass";
        private static ProfilingSampler m_ProfilingSampler = new ProfilingSampler(ProfilerTag);

        private int depthPrePass = Shader.PropertyToID("_WaterDepth");
        private const int DEPTH_ONLY_PASS_INDEX = 1;

        private bool frustrumCulling;
        
        public void Setup(bool frustrumCulling)
        {
            this.frustrumCulling = frustrumCulling;
            
            ConfigureTarget(depthPrePass);
            ConfigureClear(ClearFlag.All, Color.clear);
        }
        
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            cameraTextureDescriptor.colorFormat = RenderTextureFormat.RGFloat;
            //cameraTextureDescriptor.depthBufferBits = 32;
            cameraTextureDescriptor.msaaSamples = 1;
            cmd.GetTemporaryRT(depthPrePass, cameraTextureDescriptor);
            cmd.SetGlobalTexture(depthPrePass, depthPrePass);
        }
        
        private static readonly Plane[] frustrumPlanes = new Plane[6];
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                if (frustrumCulling) GeometryUtility.CalculateFrustumPlanes(renderingData.cameraData.camera.projectionMatrix * renderingData.cameraData.camera.worldToCameraMatrix, frustrumPlanes);
                
                //Draw all water objects with the depth-only pass
                foreach (WaterObject water in WaterObject.Instances)
                {
                    if (water.meshFilter.sharedMesh == null || water.material == null) continue;

                    if (water.material != UnderwaterRenderer.Instance.waterMaterial) continue;

                    if (frustrumCulling && !GeometryUtility.TestPlanesAABB(frustrumPlanes, water.meshRenderer.bounds)) continue;

                    cmd.DrawMesh(water.meshFilter.sharedMesh, water.transform.localToWorldMatrix, water.material, 0, DEPTH_ONLY_PASS_INDEX);
                }
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
        
        public override void FrameCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(depthPrePass);
        }
    }
}
#endif