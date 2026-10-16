// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

extension ReaderView {
    var readerBarBackground: some ShapeStyle {
        AnyShapeStyle(readerChromeIsBrightMode ? Color.white : Color.black)
    }

    var readerChromeLuminance: CGFloat {
        if isVerticalReader, logicalPages.indices.contains(pageIndex),
           let item = verticalRenderItems.first(where: { $0.logicalPageIndex == pageIndex }),
           let luminance = pageLuminanceByRenderItemID[item.id] { return luminance }
        guard !isVerticalReader,
              pagerItems.indices.contains(pagerDisplayIndex),
              case .render(let item) = pagerItems[pagerDisplayIndex],
              let focused = item.members.first(where: { $0.logicalPageIndex == pageIndex }),
              let luminance = pageLuminanceByRenderItemID[focused.id] else {
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
        AnyShapeStyle(readerChromeIsBrightMode ? Color.white : Color.black)
    }

    var readingModeSymbol: String {
        switch activeReaderMode {
        case .pagerDefault:
            return "rectangle.split.1x2"
        case .pagerLTR:
            return "text.book.closed"
        case .pagerRTL:
            return "text.book.closed.fill"
        case .verticalPaged:
            return "rectangle.portrait"
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

// Chrome-only layout and accessibility; page rendering and motion remain untouched.
struct ReaderChromeOptions<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.adaptive(minimum: 110), spacing: 8)],
            spacing: 8
        ) { content }
    }
}

struct ReaderChromePresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let foreground: Color

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if contrast == .increased {
                    Rectangle().fill(foreground).frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }
}

struct ReaderChromeIdentity<Close: View, Identity: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let close: Close
    let identity: Identity
    let actions: Actions

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalIdentity
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { close; identity; Spacer(minLength: 0); actions }
                verticalIdentity
            }
        }
    }

    private var verticalIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { close; Spacer(minLength: 0); actions }
            identity
        }
    }
}
