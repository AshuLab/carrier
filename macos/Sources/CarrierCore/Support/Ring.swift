/// Whether a ring turns: only while the window can be seen and the system does not ask for less motion.
public func ringAnimates(windowVisible: Bool, reduceMotion: Bool) -> Bool {
    windowVisible && reduceMotion == false
}
