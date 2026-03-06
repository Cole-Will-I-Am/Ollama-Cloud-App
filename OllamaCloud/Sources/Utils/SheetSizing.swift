import SwiftUI

enum SeerSheetSize {
    static let modelPicker = CGSize(width: 420, height: 520)
    static let parameters = CGSize(width: 520, height: 640)
}

extension View {
    @ViewBuilder
    func macSheetFixedSize(_ size: CGSize) -> some View {
        #if os(macOS)
        self.frame(
            minWidth: size.width,
            idealWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            idealHeight: size.height,
            maxHeight: size.height,
            alignment: .topLeading
        )
        #else
        self
        #endif
    }
}
