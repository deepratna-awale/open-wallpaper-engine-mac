# Runs inside qrenderdoc (--python). job_draws.json {ident, we, out, projects:[...]}: for each project, opens it on
# monitor 0, waits, captures one frame, and logs every draw call (name, indices, instances, outputs). Saves the swapchain.
import os, json, time, subprocess
JOB = json.load(open(r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\job_draws.json'))
OUT = JOB['out']; os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, 'rd_draws_report.txt'), 'w', encoding='utf-8')
def P(*a):
    log.write(' '.join(str(x) for x in a) + '\n'); log.flush()
try:
    import renderdoc as rd
    capdir = r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\cap'
    before = set(os.listdir(capdir))
    tc = rd.CreateTargetControl('', int(JOB['ident']), 'claude-draws', True)
    jobs = []
    for pj in JOB['projects']:
        subprocess.call([JOB['we'] + r'\wallpaper64.exe', '-control', 'openWallpaper', '-file',
                         JOB['we'] + r'\projects\myprojects\%s\project.json' % pj, '-monitor', str(JOB.get('monitor', 0))])
        time.sleep(6)
        tc.TriggerCapture(1); t0 = time.time()
        while time.time() - t0 < 30:
            m = tc.ReceiveMessage(None)
            if m.type == rd.TargetControlMessageType.NewCapture and os.path.basename(m.newCapture.path) not in before:
                before.add(os.path.basename(m.newCapture.path)); jobs.append((pj, m.newCapture.path)); break
    tc.Shutdown()
    for pj, path in jobs:
        cap = rd.OpenCaptureFile(); cap.OpenFile(path, '', None)
        st, ctrl = cap.OpenCapture(rd.ReplayOptions(), None)
        sf = ctrl.GetStructuredFile(); acts = []
        def walk(a):
            for x in a: acts.append(x); walk(x.children)
        walk(ctrl.GetRootActions())
        draws = [a for a in acts if a.flags & rd.ActionFlags.Drawcall]
        P('==', pj, 'capture', path, 'draws', len(draws))
        for a in draws:
            P('  eid %d %s idx=%d inst=%d' % (a.eventId, a.GetName(sf), a.numIndices, a.numInstances))
        ctrl.SetFrameEvent(acts[-1].eventId, True)
        for t in ctrl.GetTextures():
            if t.creationFlags & rd.TextureCategory.SwapBuffer:
                sv = rd.TextureSave(); sv.resourceId = t.resourceId; sv.destType = rd.FileType.PNG; sv.alpha = rd.AlphaMapping.Discard
                ctrl.SaveTexture(sv, os.path.join(OUT, pj + '.png'))
        ctrl.Shutdown(); cap.Shutdown()
except Exception:
    import traceback; P('EXCEPTION', traceback.format_exc())
finally:
    log.close(); os._exit(0)
