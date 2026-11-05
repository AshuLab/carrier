/// The size of a sheet over a window: three quarters of it, never smaller than the content needs and never larger than the window less a
/// margin, so on the smallest window it is the size the sheets were drawn for and on a big one it grows with it.
public func sheetSize(windowWidth: Double, windowHeight: Double) -> (width: Double, height: Double) {
    (sheetSide(windowWidth, floor: 820), sheetSide(windowHeight, floor: 560))
}

private func sheetSide(_ window: Double, floor: Double) -> Double {
    var side = window * 0.75
    if side < floor { side = floor }
    if side > window - 40 { side = window - 40 }
    return side
}
