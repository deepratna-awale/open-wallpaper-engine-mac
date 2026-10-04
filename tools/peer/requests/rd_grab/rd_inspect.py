# Runs inside qrenderdoc (--python). Opens one .rdc (job_inspect.json {rdc, out, events}) and dumps, per event: shaders,
# their constant buffers (incl. g_BlendMap), bound SRV textures, vertex input layout, and saves each bound texture as PNG.
import os, json
JOB = json.load(open(r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\job_inspect.json'))
OUT = JOB['out']; os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, 'inspect_report.txt'), 'w', encoding='utf-8')
def P(*a):
    log.write(' '.join(str(x) for x in a) + '\n'); log.flush()
try:
    import renderdoc as rd
    cap = rd.OpenCaptureFile(); cap.OpenFile(JOB['rdc'], '', None)
    st, ctrl = cap.OpenCapture(rd.ReplayOptions(), None)
    texs = {t.resourceId: t for t in ctrl.GetTextures()}
    names = {r.resourceId: r.name for r in ctrl.GetResources()}
    for eid in JOB['events']:
        ctrl.SetFrameEvent(eid, True); ps = ctrl.GetPipelineState()
        P('\n=== event', eid)
        for o in ps.GetOutputTargets():
            if o.resource in texs: t = texs[o.resource]; P('  RT', names.get(o.resource), t.width, t.height, t.format.Name())
        for a in ps.GetVertexInputs():
            P('  VTX', a.name, a.format.Name(), 'buf', a.vertexBuffer, 'off', a.byteOffset)
        for stage in (rd.ShaderStage.Vertex, rd.ShaderStage.Pixel):
            refl = ps.GetShaderReflection(stage)
            if not refl: continue
            P(' ', stage, 'shader', names.get(ps.GetShader(stage)))
            for i, cb in enumerate(refl.constantBlocks):
                b = ps.GetConstantBlock(stage, i, 0)
                vs = ctrl.GetCBufferVariableContents(ps.GetGraphicsPipelineObject(), ps.GetShader(stage), stage, ps.GetShaderEntryPoint(stage), i, b.descriptor.resource, b.descriptor.byteOffset, b.descriptor.byteSize)
                def dump(vv, pre=''):
                    for v in vv:
                        if v.members: dump(v.members, pre + v.name + '.')
                        else: P('    cb%d %s%s = %s' % (i, pre, v.name, [round(x, 4) for x in list(v.value.f32v)[:v.rows * v.columns]]))
                dump(vs)
            if stage == rd.ShaderStage.Pixel:
                for ro in ps.GetReadOnlyResources(stage):
                    r = ro.descriptor.resource
                    if r in texs:
                        t = texs[r]; P('    SRV', ro.access.index, names.get(r), t.width, t.height, t.format.Name())
                        s = rd.TextureSave(); s.resourceId = r; s.destType = rd.FileType.PNG; s.alpha = rd.AlphaMapping.Preserve
                        ctrl.SaveTexture(s, os.path.join(OUT, 'ev%d_srv%d.png' % (eid, ro.access.index)))
    ctrl.Shutdown(); cap.Shutdown()
except Exception:
    import traceback; P('EXCEPTION', traceback.format_exc())
finally:
    log.close(); os._exit(0)
