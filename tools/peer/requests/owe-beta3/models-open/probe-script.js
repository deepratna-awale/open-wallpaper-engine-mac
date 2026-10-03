'use strict';
// Origin script for the models-open probes (5.24 bone angle units, 5.31 impulse without a bone, 5.5 camera transforms).
let t = 0, done = false, next = 0;
function fmt(v) { return v && v.x !== undefined ? v.x.toFixed(4) + ',' + v.y.toFixed(4) + ',' + v.z.toFixed(4) : JSON.stringify(v); }
export function update(value) {
	t += engine.frametime;
	if (!done) {
		done = true;
		try { console.log('MO 531 noarg -> ' + JSON.stringify(thisLayer.applyBonePhysicsImpulse())); } catch (e) { console.log('MO 531 noarg threw: ' + e); }
		try { console.log('MO 531 vecs-only -> ' + JSON.stringify(thisLayer.applyBonePhysicsImpulse(new Vec3(0, 0, 0), new Vec3(0, 0, 45)))); } catch (e) { console.log('MO 531 vecs-only threw: ' + e); }
		try { console.log('MO 531 reset noarg -> ' + JSON.stringify(thisLayer.resetBonePhysicsSimulation())); } catch (e) { console.log('MO 531 reset noarg threw: ' + e); }
	}
	if (t >= next) {
		next += 0.5;
		let a, ar, c;
		try { a = fmt(thisLayer.getLocalBoneAngles('tail')); } catch (e) { a = 'threw ' + e; }
		try { ar = fmt(thisLayer.getLocalBoneAngles(1)); } catch (e) { ar = 'threw ' + e; }
		try { const ct = thisScene.getCameraTransforms(); c = JSON.stringify({ eye: fmt(ct.eye), center: fmt(ct.center), up: fmt(ct.up) }); } catch (e) { c = 'threw ' + e; }
		console.log('MO t=' + t.toFixed(2) + ' tailAngles=' + a + ' bone1Angles=' + ar + ' cam=' + c);
	}
	return value;
}
