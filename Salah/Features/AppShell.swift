import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var container: AppContainer

    private var preferredScheme: ColorScheme? {
        switch container.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        Group {
            if container.settings.onboardingComplete {
                RootTabView(container: container)
            } else {
                OnboardingFlow(container: container)
            }
        }
        .environment(\.salahPalette, container.settings.palette)
        .environment(\.locale, container.settings.language.locale)
        .id(container.settings.language)
        .tint(container.settings.palette.accent)
        .preferredColorScheme(preferredScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, container.settings.onboardingComplete {
                Task { await reconcileReminders() }
            }
        }
    }

    private func reconcileReminders() async {
        guard container.settings.reminders.values.contains(where: \.enabled) || container.settings.charityReminder.enabled,
              await container.notificationScheduler.authorizationStatus() == .authorized else { return }
        await ReminderCoordinator.reconcile(container: container)
    }
}

struct RootTabView: View {
    @Bindable var container: AppContainer

    var body: some View {
        SystemTabRootView(container: container)
    }
}

private struct SystemTabRootView: View {
    @Bindable var container: AppContainer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var router = container.router
        if #available(iOS 18.0, *), horizontalSizeClass == .regular {
            TabView(selection: $router.selectedTab) {
                Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                    NavigationStack { TodayView(container: container) }
                }
                Tab(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage, value: AppTab.calendar) {
                    NavigationStack { PrayerCalendarView(container: container) }
                }
                Tab(AppTab.tracker.title, systemImage: AppTab.tracker.systemImage, value: AppTab.tracker) {
                    NavigationStack { TrackerView(container: container) }
                }
                Tab(AppTab.discover.title, systemImage: AppTab.discover.systemImage, value: AppTab.discover) {
                    NavigationStack { DiscoverView(container: container) }
                }
                Tab(AppTab.more.title, systemImage: AppTab.more.systemImage, value: AppTab.more) {
                    NavigationStack { MoreView(container: container) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $router.selectedTab) {
                NavigationStack { TodayView(container: container) }
                    .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
                    .tag(AppTab.today)

                NavigationStack { PrayerCalendarView(container: container) }
                    .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage) }
                    .tag(AppTab.calendar)

                NavigationStack { TrackerView(container: container) }
                    .tabItem { Label(AppTab.tracker.title, systemImage: AppTab.tracker.systemImage) }
                    .tag(AppTab.tracker)

                NavigationStack { DiscoverView(container: container) }
                    .tabItem { Label(AppTab.discover.title, systemImage: AppTab.discover.systemImage) }
                    .tag(AppTab.discover)

                NavigationStack { MoreView(container: container) }
                    .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.systemImage) }
                    .tag(AppTab.more)
            }
        }
    }
}

private struct PadSidebarRootView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette

    var body: some View {
        @Bindable var router = container.router
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {

                VStack(spacing: 6) {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            router.selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                .padding(.horizontal, 12)
                                .foregroundStyle(router.selectedTab == tab ? .white : .white.opacity(0.82))
                                .background(
                                    router.selectedTab == tab ? .white.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(router.selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.heroGradient)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            NavigationStack {
                AppTabContent(tab: router.selectedTab, container: container)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct PadBottomTabRootView: View {
    @Bindable var container: AppContainer

    var body: some View {
        @Bindable var router = container.router
        NavigationStack {
            AppTabContent(tab: router.selectedTab, container: container)
        }
        .safeAreaInset(edge: .bottom) {
            PadBottomTabBar(selection: $router.selectedTab)
        }
    }
}

private struct PadBottomTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.salahPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? palette.accent : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct AppTabContent: View {
    let tab: AppTab
    @Bindable var container: AppContainer

    var body: some View {
        switch tab {
        case .today:
            TodayView(container: container)
        case .calendar:
            PrayerCalendarView(container: container)
        case .tracker:
            TrackerView(container: container)
        case .discover:
            DiscoverView(container: container)
        case .more:
            MoreView(container: container)
        }
    }
}
