/// The size of a sheet over a window: three quarters of it, never smaller than the content needs and never larger than the window less a
/// margin, so on the smallest window it is the size the sheets were drawn for and on a big one it grows with it. A sheet that reads badly
/// when wide passes `maxWidth`, and stops growing there while its height still follows the window.
public func sheetSize(windowWidth: Double, windowHeight: Double, maxWidth: Double = .infinity) -> (width: Double, height: Double) {
    (min(sheetSide(windowWidth, floor: 820), maxWidth), sheetSide(windowHeight, floor: 560))
}

private func sheetSide(_ window: Double, floor: Double) -> Double {
    var side = window * 0.75
    if side < floor { side = floor }
    if side > window - 40 { side = window - 40 }
    return side
}
