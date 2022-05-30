//Stylized Water 2: Underwater Rendering extension
//Staggart Creations (http://staggart.xyz)
//Copyright protected under Unity Asset Store EULA

using UnityEngine;
using UnityEngine.Rendering;
#if URP
using UnityEngine.Rendering.Universal;

namespace StylizedWater2
{
    class UnderwaterPost : ScriptableRenderPass
    {
        private const string ProfilerTag = "Underwater Rendering: Post Processing";
        private static ProfilingSampler m_ProfilingSampler = new ProfilingSampler(ProfilerTag);

        private UnderwaterResources resources;
        private UnderwaterRenderFeature.Settings settings;
        private UnderwaterRenderFeature renderFeature;

        private int _DistortionNoise = Shader.PropertyToID("_DistortionNoise");
        private int _DistortionSphere = Shader.PropertyToID("_DistortionSphere");

        private const string DistortionSSKeyword = "_SCREENSPACE_DISTORTION";
        private const string DistortionWSKeyword = "_CAMERASPACE_DISTORTION";
        private const string BlurKeyword = "BLUR";
        
        private Material Material;
        private Material DistortionSphereMaterial;

        public UnderwaterPost(UnderwaterRenderFeature renderFeature)
        {
            this.renderFeature = renderFeature;
            this.resources = renderFeature.resources;
            Material = UnderwaterRenderFeature.CreateMaterial(ProfilerTag, renderFeature.resources.postProcessShader);
        }

        private RenderTargetHandle mainTexHandle;
        private int mainTexID = Shader.PropertyToID("_SourceTex");
        private RenderTargetIdentifier cameraColorTarget;
        
        public void Setup(UnderwaterRenderFeature.Settings settings, ScriptableRenderer renderer)
        {
            this.settings = settings;
            #if !URP_10_0_OR_NEWER
            //otherwise fetched in Execute function, no longer allowed from a ScriptableRenderFeature setup function (target may be not be created yet, or was disposed)
            this.cameraColorTarget = renderer.cameraColorTarget;
            #endif

            if (settings.allowDistortion && settings.distortionMode == UnderwaterRenderFeature.Settings.DistortionMode.CameraSpace && DistortionSphereMaterial == null)
            {
                DistortionSphereMaterial = CoreUtils.CreateEngineMaterial(resources.distortionShader);
            }
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
            
            CoreUtils.SetKeyword(Material, BlurKeyword, UnderwaterRenderer.Instance.enableBlur && settings.allowBlur);
            CoreUtils.SetKeyword(Material, DistortionSSKeyword, UnderwaterRenderer.Instance.enableDistortion && settings.allowDistortion && settings.distortionMode == UnderwaterRenderFeature.Settings.DistortionMode.ScreenSpace);
            CoreUtils.SetKeyword(Material, DistortionWSKeyword, UnderwaterRenderer.Instance.enableDistortion && settings.allowDistortion && settings.distortionMode == UnderwaterRenderFeature.Settings.DistortionMode.CameraSpace);
        }

        public void ConfigurePass(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            mainTexHandle = new RenderTargetHandle();
            mainTexHandle.id = mainTexID;
            
            cmd.GetTemporaryRT(mainTexHandle.id, cameraTextureDescriptor);
            cmd.SetGlobalTexture(mainTexHandle.id, mainTexID);
            
            if (UnderwaterRenderer.Instance.enableDistortion && settings.allowDistortion && settings.distortionMode == UnderwaterRenderFeature.Settings.DistortionMode.CameraSpace)
            {
                cameraTextureDescriptor.colorFormat = RenderTextureFormat.R8;
                cameraTextureDescriptor.msaaSamples = 1;
                cmd.GetTemporaryRT(_DistortionSphere, cameraTextureDescriptor);
                cmd.SetGlobalTexture(_DistortionSphere, _DistortionSphere);
            }
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
                
                if (UnderwaterRenderer.Instance.enableDistortion && settings.allowDistortion)
                {
                    cmd.SetGlobalTexture(_DistortionNoise, resources.distortionNoise);

                    if (settings.distortionMode == UnderwaterRenderFeature.Settings.DistortionMode.CameraSpace)
                    {
                        cmd.SetRenderTarget(_DistortionSphere);
                        cmd.DrawMesh(resources.geoSphere, Matrix4x4.TRS(renderingData.cameraData.camera.transform.position, Quaternion.identity, Vector3.one * renderingData.cameraData.camera.projectionMatrix.inverse.m11), DistortionSphereMaterial);
                    }
                }
                
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
            cmd.ReleaseTemporaryRT(_DistortionSphere);
        }
    }

}
#endif