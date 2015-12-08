import Cocoa

private let NR_FLARES               = 400
private let VELOCITY: Float         = 0.3
private let GRAVITY: Float          = -0.08

private let COLORS: [Color4] = [
    Color4(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
    Color4(r: 0.0, g: 1.0, b: 0.0, a: 1.0),
    Color4(r: 1.0, g: 1.0, b: 0.0, a: 1.0),
    Color4(r: 0.0, g: 1.0, b: 1.0, a: 1.0),
    Color4(r: 1.0, g: 0.0, b: 0.5, a: 1.0),
    Color4(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
    Color4(r: 1.0, g: 0.2, b: 0.2, a: 1.0),
]

private func get_random_color() -> Color4 {
    let i = random_range(0, COLORS.count - 1)
    return COLORS[i]
}


// Return a position.
// Simulate air drag - velocity tapers off exponentially
private func _get_flight(vel: Float, secs: Float) -> Float {
    let x = log10f(1 + secs * 10.0)
    return x * vel
}


// Record the starting point of a flare.
// We have the entire trajectory (path) from the beginning.
private struct Flare {
    let velocity_vec: Vector3
    let start_time: TimeUS
    let duration_secs: Float

    // How far back the trail goes (plume mode)
    let trail_secs: Float  

    let color: Color4
    let size: Float

    func getSecondsElapsed(time: TimeUS) -> Float {
        if time < start_time {
            return 0
        }
        return Float(time - start_time) / 1000000
    }

    func pointAtTime(secs: Float, orig_pos: Vector3) -> Vector3 {
        var ret = orig_pos
        ret.x += _get_flight(velocity_vec.x, secs: secs)
        ret.y += _get_flight(velocity_vec.y, secs: secs)
        //ret.z += _get_flight(velocity_vec.z, secs: secs)

        // Gravity
        ret.y += (GRAVITY / Float(2.0) * secs * secs)

        return ret
    }

    func colorAtTime(secs: Float) -> Color4 {
        // linear fade out is fine
        let percent = secs / duration_secs
        var ret = color
        ret.a *= (1 - percent)
        return ret
    }
}


private class Firework {
    var pos: Vector3
    let type: Int
    var m_flares = [Flare]()

    init(pos: Vector3, type: Int) {
        precondition(type >= 0)
        precondition(type <= 1)
        self.pos = pos
        self.type = type
    }

    func add_flares(count: Int, start_time: TimeUS, aspect_x: Float) {
        let orig_color = get_random_color()
        for _ in 0..<count {
            var velocity = RandomUniformUnitVector()

            // for now, don't animate z, to stay in device space
            velocity.z = 0

            // Aspect correction.  Otherwise we get ovalish fireworks.
            velocity.x *= aspect_x

            // tune the velocity
            velocity.x *= VELOCITY
            velocity.y *= VELOCITY

            var color = orig_color
            color.r += random_range(-0.3, 0.3)
            color.b += random_range(-0.3, 0.3)
            color.g += random_range(-0.3, 0.3)
            color.a = random_range(0.7, 4.0)

            let duration_secs = random_range(0.5, 3.0)
            let trail_secs = random_range(0.3, 0.7)
            let size = random_range(0.003, 0.005)

            let f = Flare(velocity_vec: velocity,
                        start_time: start_time,
                        duration_secs: duration_secs,
                        trail_secs: trail_secs,
                        color: color, 
                        size: size)
            m_flares.append(f)
        }
    }
}


class FireworkScene {
    private var m_fireworks = [Firework]()
    private var next_launch: TimeUS
    private var next_stats: TimeUS
    private var stats_max_bv: Int
    private var stats_max_bc: Int
    private var x_aspect_ratio: Float

    init() {
        next_launch = get_current_timestamp()
        next_stats = 0
        stats_max_bv = 0
        stats_max_bc = 0
        x_aspect_ratio = 0.1
        arm_stats()
    }
    
    func set_screen_size(width width: Float, height: Float) {
        print("size change \(width) x \(height)")
        let v = height / width
        x_aspect_ratio = v
    }

    func arm_stats() {
        self.next_stats = get_current_timestamp() + 1000000
        self.stats_max_bv = 0
        self.stats_max_bc = 0
    }

    func launch_firework(current_time: TimeUS) {
        let pos_x = random_range(-0.8, 0.8)
        let pos_y = random_range(0.0, 0.8)

        // It's cool to set this at -0.2 and see the fireworks as they pop through the back plane
        let pos_z = Float(0.1)

        let pos = Vector3(x: pos_x, y: pos_y, z: pos_z)

        let type = random_range(0, 1)
        let fw = Firework(pos: pos, type: type)
        fw.add_flares(NR_FLARES, start_time: current_time,
            aspect_x: x_aspect_ratio)
        m_fireworks.append(fw)

        //print("launching \(m_fireworks.count) \(type)")

        while m_fireworks.count > 10 {
            m_fireworks.removeAtIndex(0)
        }
    }

    func update(inout bv bv: BufferWrapper, inout bc: BufferWrapper) {
        let curtime = get_current_timestamp()

        if curtime > next_launch {
            launch_firework(curtime)
            next_launch = curtime + TimeUS(random_range(100000, 700000))
        }

        for fw in m_fireworks {
            if fw.type == 0 {
                // classic particle only
                for flare in fw.m_flares {
                    render_flare_simple(fw, flare: flare, 
                            time: curtime, bv: &bv, bc: &bc) 
                }
            } else {
                // long trail
                for flare in fw.m_flares {
                    render_flare_trail(fw, flare: flare, 
                            time: curtime, bv: &bv, bc: &bc) 
                }
            }
        }

        if bv.pos > self.stats_max_bv {
            self.stats_max_bv = bv.pos
        }
        if bc.pos > self.stats_max_bc {
            self.stats_max_bc = bc.pos
        }
        if self.next_stats < curtime {
            print("stats: bc \(self.stats_max_bc)")
            print("stats: bv \(self.stats_max_bv)")
            self.arm_stats()
        }
    }
}


private func render_flare_simple(fw: Firework, flare: Flare, time: TimeUS, 
        inout bv: BufferWrapper, inout bc: BufferWrapper) {
    let secs = flare.getSecondsElapsed(time)
    if secs > flare.duration_secs {
        return
    }
    let p = flare.pointAtTime(secs, orig_pos: fw.pos)
    var color = flare.colorAtTime(secs)
    if secs > (flare.duration_secs - 0.1) {
        // flash out
        color.a = 1.0
    }
    //print(p)
    draw_triangle_2d(&bv, p, flare.size)
    draw_triangle_color(&bc, color)
    draw_triangle_2d_ups(&bv, p, flare.size)
    draw_triangle_color(&bc, color)
}


private func render_flare_trail(fw: Firework, flare: Flare, time: TimeUS, 
        inout bv: BufferWrapper, inout bc: BufferWrapper) {

    let PLUME_FADE: Float       = 0.90
    // If this is too small, flickering happens when the dots move
    let PLUME_STEP_SECS: Float  = 0.02

    var secs = flare.getSecondsElapsed(time)
    if secs > flare.duration_secs {
        return
    }
    var color = flare.colorAtTime(secs)
    var plume_secs = Float(0)
    var size = flare.size
    var first = true

    while true {
        let p = flare.pointAtTime(secs, orig_pos: fw.pos)
        draw_triangle_2d(&bv, p, size)
        draw_triangle_color(&bc, color)
        if first {
            draw_triangle_2d_ups(&bv, p, size)
            draw_triangle_color(&bc, color)
            first = false
        }
        
        size *= 0.95
        color.a *= PLUME_FADE
        secs -= PLUME_STEP_SECS
        plume_secs += PLUME_STEP_SECS
        if secs < 0 || plume_secs > flare.trail_secs {
            return
        }
    }
}


func draw_triangle_2d(inout b: BufferWrapper, _ pos: Vector3, _ size: Float) {
    guard b.has_available(12) else {
        return
    }

    b.append_raw(pos.x - size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x + size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x)
    b.append_raw(pos.y + size)
    b.append_raw(pos.z)
    b.append_raw(1.0)
}


// upside down
private func draw_triangle_2d_ups(inout b: BufferWrapper, _ pos: Vector3, _ size: Float) {
    guard b.has_available(12) else {
        return
    }

    b.append_raw(pos.x - size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x + size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x)
    b.append_raw(pos.y - size)
    b.append_raw(pos.z)
    b.append_raw(1.0)
}


private func draw_triangle_color(inout b: BufferWrapper, _ color: Color4) {
    guard b.has_available(12) else {
        return
    }

    b.append_raw_color4(color)
    b.append_raw_color4(color)
    b.append_raw_color4(color)
}