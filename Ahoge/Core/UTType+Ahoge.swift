// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  UTType+Ahoge.swift
//  Ahoge
//

import UniformTypeIdentifiers

extension UTType {
    static var ahogeCBZ: UTType {
        UTType(filenameExtension: "cbz") ?? .zip
    }

    static var ahogeEPUB: UTType {
        UTType(filenameExtension: "epub") ?? .data
    }
}
