# Runs inside qrenderdoc (--python). Triggers a capture of the running WE (target ident from launch), then analyses
# the draws that touch a cloth pixel: shader constants, bound textures, and pixel history. Writes mg7_report.txt.
import os
log = open(r'K:\DeepWorkspace\wem-images2\tools\peer\models_gt\mg7\mg7_report.txt', 'w', encoding='utf-8')
log.write('started\n'); log.flush()
import renderdoc as rd, time, sys, json

OUT = r'K:\DeepWorkspace\wem-images2\tools\peer\models_gt\mg7'
IDENT = int(open(os.path.join(OUT, 'ident.txt')).read().strip())
CLOTH_PX = [(1070, 410), (1020, 330), (1120, 500)]   # inside the red cloth region on the 1920x1080 monitor

def P(*a):
    log.write(' '.join(str(x) for x in a) + '\n'); log.flush()

try:
    existing = [f for f in os.listdir(OUT) if f.endswith('.rdc')]
    tc = None if existing else rd.CreateTargetControl('', IDENT, 'claude-mg7', True)
    if existing:
        path = os.path.join(OUT, sorted(existing)[-1]); P('reusing capture', path)
    if tc is None and not existing:
        P('ERROR: could not connect to target', IDENT); raise SystemExit
    if not existing:
        P('connected to', tc.GetTarget(), 'api', tc.GetAPI(), 'pid', tc.GetPID())
        time.sleep(1); tc.TriggerCapture(1); path = None; t0 = time.time()
        while time.time() - t0 < 60 and not path:
            msg = tc.ReceiveMessage(None)
            if msg.type == rd.TargetControlMessageType.NewCapture: path = msg.newCapture.path
        tc.Shutdown()
    P('capture:', path)
    if not path:
        raise SystemExit

    cap = rd.OpenCaptureFile()
    st = cap.OpenFile(path, '', None)
    st, ctrl = cap.OpenCapture(rd.ReplayOptions(), None)
    P('replay status', st)

    # final presented texture: the last action's output target
    actions = []
    def walk(a):
        for x in a:
            actions.append(x); walk(x.children)
    walk(ctrl.GetRootActions())
    draws = [a for a in actions if a.flags & rd.ActionFlags.Drawcall]
    P('actions', len(actions), 'draws', len(draws))
    texs = {t.resourceId: t for t in ctrl.GetTextures()}
    res = {r.resourceId: r.name for r in ctrl.GetResources()}
    last = draws[-1]
    ctrl.SetFrameEvent(last.eventId, True)
    outs = [o.resource for o in ctrl.GetPipelineState().GetOutputTargets() if o.resource != rd.ResourceId.Null()]
    # pick the biggest render target used by any draw as the scene target, sample the cloth pixels there
    cand = {}
    for d in draws:
        for o in d.outputs:
            if o != rd.ResourceId.Null() and o in texs:
                cand[o] = texs[o].width * texs[o].height
    depths = {}
    for d in draws:
        if d.depthOut != rd.ResourceId.Null() and d.depthOut in texs: depths.setdefault(d.depthOut, []).append(d.eventId)
    P('depth targets:', [(res.get(k, str(k)), texs[k].width, texs[k].height, str(texs[k].format.Name()), 'draws=%d' % len(v), 'events %d..%d' % (v[0], v[-1])) for k, v in depths.items()])
    P('render targets:', [(res.get(k, str(k)), texs[k].width, texs[k].height, str(texs[k].format.Name())) for k in cand])

    interesting = set()
    for rt, _ in sorted(cand.items(), key=lambda kv: -kv[1])[:4]:
        t = texs[rt]
        for (x, y) in CLOTH_PX:
            px, py = int(x * t.width / 1920), int(y * t.height / 1080)
            hist = ctrl.PixelHistory(rt, px, py, rd.Subresource(0, 0, 0), rd.CompType.Typeless)
            mods = [h for h in hist if h.Passed()]
            if mods:
                P('RT %s (%dx%d) pixel (%d,%d): %d passing modifications' % (res.get(rt, rt), t.width, t.height, px, py, len(mods)))
                for h in mods[-6:]:
                    pc = h.postMod.col.floatValue
                    P('   event %d prim %d -> post (%.3f %.3f %.3f %.3f) shaderOut (%.3f %.3f %.3f %.3f)' % (
                        h.eventId, h.primitiveID, pc[0], pc[1], pc[2], pc[3], *h.shaderOut.col.floatValue[:4]))
                    interesting.add(h.eventId)

    for eid in sorted(interesting):
        ctrl.SetFrameEvent(eid, True)
        ps = ctrl.GetPipelineState()
        act = next((a for a in actions if a.eventId == eid), None)
        P('\n=== event', eid, act.GetName(ctrl.GetStructuredFile()) if act else '')
        for stage in (rd.ShaderStage.Vertex, rd.ShaderStage.Pixel):
            refl = ps.GetShaderReflection(stage)
            if not refl:
                continue
            P(' %s shader %s entry=%s' % (stage, res.get(ps.GetShader(stage), ps.GetShader(stage)), refl.entryPoint))
            for i, cb in enumerate(refl.constantBlocks):
                bind = ps.GetConstantBlock(stage, i, 0)
                vars_ = ctrl.GetCBufferVariableContents(ps.GetGraphicsPipelineObject(), ps.GetShader(stage), stage,
                                                        ps.GetShaderEntryPoint(stage), i, bind.descriptor.resource,
                                                        bind.descriptor.byteOffset, bind.descriptor.byteSize)
                def dump(vs, pre=''):
                    for v in vs:
                        if v.members:
                            dump(v.members, pre + v.name + '.')
                        else:
                            n = v.rows * v.columns
                            vals = [round(x, 4) for x in list(v.value.f32v)[:n]]
                            P('    cb%d %s%s = %s' % (i, pre, v.name, vals))
                dump(vars_)
            if stage == rd.ShaderStage.Pixel:
                for ro in ps.GetReadOnlyResources(stage):
                    r = ro.descriptor.resource
                    if r in texs:
                        t = texs[r]
                        P('    SRV slot %s: %s %dx%d %s' % (ro.access.index, res.get(r, r), t.width, t.height, t.format.Name()))
                # combos: WE bakes combos into shader variants; the disassembly exposes #defines only indirectly
                try:
                    dis = ctrl.DisassembleShader(ps.GetGraphicsPipelineObject(), refl, '')
                    open(os.path.join(OUT, 'ps_event%d.txt' % eid), 'w', encoding='utf-8').write(dis)
                    P('    PS disassembly saved: ps_event%d.txt (%d chars)' % (eid, len(dis)))
                except Exception as e:
                    P('    disassembly failed', e)
    ctrl.Shutdown(); cap.Shutdown()
except SystemExit:
    pass
except Exception as e:
    import traceback
    P('EXCEPTION', traceback.format_exc())
finally:
    log.close()
    os._exit(0)



