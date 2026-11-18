//
//  Log.swift
//  Memora
//
//  Minimal local logging via os.Logger. Nothing is sent off-device.
//

import Foundation
import os

public enum Log {
    private static let subsystem = "app.memora"

    public static let importer = Logger(subsystem: subsystem, category: "importer")
    public static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let export = Logger(subsystem: subsystem, category: "export")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
