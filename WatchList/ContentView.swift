//
//  ContentView.swift
//  WatchList
//
//  The home screen now lives in LibraryView.swift, hosted by RootView.swift.
//  This file is kept as a thin compatibility shim.
//

import SwiftUI

struct ContentView: View {
	var body: some View {
		RootView()
	}
}

#Preview {
	ContentView()
}
