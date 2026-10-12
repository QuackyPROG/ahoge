// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ReaderViewModels.swift
//  Ahoge
//

enum ReaderPagerItem: Identifiable {
    case previousChapter
    case render(ReaderRenderItem)
    case nextChapter

    var id: String {
        switch self {
        case .previousChapter:
            return "transition-previous"
        case .render(let item):
            return item.id
        case .nextChapter:
            return "transition-next"
        }
    }
}

enum ReaderContentLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}
