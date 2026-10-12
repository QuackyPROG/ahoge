// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

extension ReaderView {
    var readerBarBackground: some ShapeStyle {
        AnyShapeStyle(.thinMaterial)
    }

    var readerChromeLuminance: CGFloat {
        guard !isVerticalReader,
              pagerItems.indices.contains(pagerDisplayIndex),
              case .render(let item) = pagerItems[pagerDisplayIndex],
              let luminance = pageLuminanceByRenderItemID[item.id] else {
            return 0.5
        }
        return luminance
    }

    var readerChromeIsBrightMode: Bool {
        readerChromeLuminance > 0.62
    }

    var readerChromeForegroundColor: Color {
        readerChromeIsBrightMode ? .black.opacity(0.9) : .white
    }

    var readerPillTintColor: Color {
        readerChromeIsBrightMode ? .black : .white
    }

    var readerPillRegularOpacity: Double {
        readerChromeIsBrightMode ? 0.08 : 0.07
    }

    var readerPillProminentOpacity: Double {
        readerChromeIsBrightMode ? 0.16 : 0.14
    }

    var readerCapsuleBackground: some ShapeStyle {
        AnyShapeStyle(.thinMaterial)
    }

    var readingModeSymbol: String {
        switch activeReaderMode {
        case .pagerDefault:
            return "rectangle.split.1x2"
        case .pagerLTR:
            return "text.book.closed"
        case .pagerRTL:
            return "text.book.closed.fill"
        case .vertical:
            return "rectangle.stack"
        case .webtoon:
            return "rectangle.portrait.on.rectangle.portrait"
        }
    }

    var orientationSymbol: String {
        switch model.state.readerPreferences.orientation {
        case .system, .portrait:
            return "iphone"
        case .landscape:
            return "iphone.landscape"
        }
    }

    var spreadBehaviorTitle: String {
        switch model.state.readerPreferences.spreadBehavior {
        case .fullPage:
            return "Full"
        case .autoSplit:
            return "Split"
        }
    }

    var spreadBehaviorSymbol: String {
        switch model.state.readerPreferences.spreadBehavior {
        case .fullPage:
            return "rectangle"
        case .autoSplit:
            return "rectangle.split.1x2"
        }
    }

    var chapterLeadingIcon: String {
        isRTLPager ? "chevron.right" : "chevron.left"
    }

    var chapterTrailingIcon: String {
        isRTLPager ? "chevron.left" : "chevron.right"
    }
}
