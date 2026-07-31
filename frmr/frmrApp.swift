//
//  frmrApp.swift
//  frmr
//
//  Created by John Zaw on 7/31/26.
//

import SwiftUI
import CoreData

@main
struct frmrApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
