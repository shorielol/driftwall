import DriftwallCore
import SwiftUI

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typeface.display(38))
                    .displayTracking(38)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(Theme.Typeface.body).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, 92)
    }
}

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var query = CatalogQuery()
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = query.apply(to: model.allWallpapers)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Explore", subtitle: "\(results.count) live wallpapers · \(results.filter(\.is4K).count) in 4K, none below 1080p") {
                    SortMenu(sort: $query.sort)
                }
                searchField
                categoryChips
                if results.isEmpty {
                    EmptyState(title: "Nothing matches", message: "Try a different word or clear the category filter.")
                } else {
                    WallpaperGrid(wallpapers: results)
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.never)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Search aurora, rain, neon city, ocean…", text: $query.text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !query.text.isEmpty {
                Button { query.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .glassCapsule()
        .padding(.horizontal, Theme.Space.gutter)
    }

    private var categoryChips: some View {
        let customCategories = Set(model.customWallpapers.map(\.category)).sorted()
        let categories = [OriginalScene.category] + model.catalog.categories + customCategories
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", isOn: query.category == nil) { query.category = nil }
                ForEach(categories, id: \.self) { category in
                    chip(category, isOn: query.category == category) {
                        query.category = query.category == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Theme.Motion.standard) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? Color.black : .white)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background { if isOn { Capsule().fill(Color.white) } }
                .glassCapsule(interactive: true)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct SortMenu: View {
    @Binding var sort: WallpaperSort

    var body: some View {
        GlassSegmented(options: WallpaperSort.allCases.map { ($0, $0.label) }, selection: $sort)
    }
}

struct PopularView: View {
    @Environment(AppModel.self) private var model
    @State private var sort: WallpaperSort = .popular

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Popular", subtitle: subtitle) { SortMenu(sort: $sort) }
                WallpaperGrid(wallpapers: CatalogQuery(sort: sort).apply(to: model.catalog.wallpapers))
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.never)
    }

    private var subtitle: String {
        switch sort {
        case .popular: "Ranked by how often they top their source's charts"
        case .newest: "Most recent drops first"
        case .longest: "Longest loops first"
        case .title: "Alphabetical"
        }
    }
}
