'use strict';

// SceneScript for the puppet layer's `origin` (Properties → Origin → the script icon).
// Moves the layer 200 px right at 2 s and back at 5 s, gives the tail an impulse at 6 s,
// resets it at 8 s, and logs the tail's world matrix and angles every frame until 9 s.
let t = 0;
let impulsed = false;
let reset = false;

export function update(value) {
	const dt = engine.frametime;
	t += dt;
	value.x = (t >= 2 && t < 5) ? 1160 : 960;
	value.y = 540;
	if (t >= 6 && !impulsed) {
		impulsed = true;
		thisLayer.applyBonePhysicsImpulse('tail', new Vec3(0, 0, 0), new Vec3(0, 0, 45));
	}
	if (t >= 8 && !reset) {
		reset = true;
		thisLayer.resetBonePhysicsSimulation('tail');
	}
	if (t < 9) {
		const m = thisLayer.getBoneTransform('tail').m;
		const a = thisLayer.getLocalBoneAngles('tail');
		console.log('BP ' + t.toFixed(5) + ' ' + dt.toFixed(6) + ' ' + value.x + ' ' +
			[m[0], m[1], m[4], m[5], m[12], m[13]].map(function (v) { return v.toFixed(4); }).join(' ') +
			' ' + a.z.toFixed(5));
	}
	return value;
}
