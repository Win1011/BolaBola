//
//  IOSOnboardingView.swift
//

import AuthenticationServices
import HealthKit
import SwiftUI
import UserNotifications

struct IOSOnboardingView: View {
    var onDone: () -> Void

    @State private var stepIndex = 0
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var healthRequested = false
    @State private var userNickname = ""
    @State private var birthDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .now
    @State private var selectedGender: OnboardingGender?
    @State private var bolaNickname = ""

    private let healthStore = HKHealthStore()

    var body: some View {
        ZStack(alignment: .top) {
            BolaLifeAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topChrome

                TabView(selection: $stepIndex) {
                    WelcomeLoginPage(onContinue: { stepIndex = 1 })
                        .tag(0)
                    IntroCompanionPage(onContinue: { stepIndex = 2 })
                        .tag(1)
                    LevelUpPage(onContinue: { stepIndex = 3 })
                        .tag(2)
                    NotificationPermissionPage(
                        status: notificationStatus,
                        onAllow: requestNotifications,
                        onSkip: { stepIndex = 4 }
                    )
                    .tag(3)
                    HealthRhythmPage(
                        requested: healthRequested,
                        onContinue: requestHealthAccess
                    )
                    .tag(4)
                    QuestionIntroPage(onContinue: { stepIndex = 6 })
                        .tag(5)
                    UserNicknamePage(
                        nickname: $userNickname,
                        onContinue: { stepIndex = 7 }
                    )
                    .tag(6)
                    BirthdayPage(
                        birthDate: $birthDate,
                        onContinue: { stepIndex = 8 }
                    )
                    .tag(7)
                    GenderPage(
                        selectedGender: $selectedGender,
                        onContinue: { stepIndex = 9 }
                    )
                    .tag(8)
                    BolaNicknamePage(
                        nickname: $bolaNickname,
                        onContinue: { stepIndex = 10 }
                    )
                    .tag(9)
                    ReadyPage(onEnter: finishOnboarding)
                        .tag(10)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: stepIndex)
            }
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            let draft = OnboardingDraft.load()
            userNickname = draft.userNickname
            birthDate = draft.birthDate
            selectedGender = draft.gender
            bolaNickname = draft.bolaNickname
        }
        .onChange(of: userNickname) { _, _ in persistDraft() }
        .onChange(of: birthDate) { _, _ in persistDraft() }
        .onChange(of: selectedGender) { _, _ in persistDraft() }
        .onChange(of: bolaNickname) { _, _ in persistDraft() }
    }

    @ViewBuilder
    private var topChrome: some View {
        if (5 ... 9).contains(stepIndex) {
            VStack(spacing: 0) {
                ProgressPills(currentIndex: stepIndex - 5, total: 4)
                    .padding(.top, 52)
                    .padding(.horizontal, 58)
                Spacer()
            }
            .frame(height: 78)
        } else {
            Color.clear
                .frame(height: 28)
        }
    }

    private func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationStatus = settings.authorizationStatus
                stepIndex = 4
            }
        }
    }

    private func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else {
            stepIndex = 5
            return
        }

        var types = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }

        healthStore.requestAuthorization(toShare: [], read: types) { _, _ in
            DispatchQueue.main.async {
                healthRequested = true
                UserDefaults.standard.set(true, forKey: IOSHealthHabitAnalysisModel.healthReadPromptCompletedKey)
                stepIndex = 5
            }
        }
    }

    private func persistDraft() {
        let draft = OnboardingDraft(
            userNickname: userNickname,
            birthDate: birthDate,
            gender: selectedGender,
            bolaNickname: bolaNickname
        )
        draft.save()
    }

    private func finishOnboarding() {
        persistDraft()
        BolaOnboardingState.markCompleted()
        onDone()
    }
}

private struct OnboardingDraft {
    var userNickname: String
    var birthDate: Date
    var gender: OnboardingGender?
    var bolaNickname: String

    private static let userNicknameKey = "bola_onboarding_user_nickname_v1"
    private static let birthDateKey = "bola_onboarding_birth_date_v1"
    private static let genderKey = "bola_onboarding_gender_v1"
    private static let bolaNicknameKey = "bola_onboarding_bola_nickname_v1"

    static func load() -> OnboardingDraft {
        let defaults = UserDefaults.standard
        let ts = defaults.object(forKey: birthDateKey) as? TimeInterval
        return OnboardingDraft(
            userNickname: defaults.string(forKey: userNicknameKey) ?? "",
            birthDate: ts.map(Date.init(timeIntervalSinceReferenceDate:)) ?? Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .now,
            gender: OnboardingGender(rawValue: defaults.string(forKey: genderKey) ?? ""),
            bolaNickname: defaults.string(forKey: bolaNicknameKey) ?? ""
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(userNickname, forKey: Self.userNicknameKey)
        defaults.set(birthDate.timeIntervalSinceReferenceDate, forKey: Self.birthDateKey)
        defaults.set(gender?.rawValue, forKey: Self.genderKey)
        defaults.set(bolaNickname, forKey: Self.bolaNicknameKey)
    }
}

private enum OnboardingGender: String, CaseIterable, Identifiable {
    case female
    case male
    case nonBinary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "女生"
        case .male: return "男生"
        case .nonBinary: return "其他"
        }
    }
}

private struct ProgressPills: View {
    let currentIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< total, id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? BolaTheme.accent : Color.white.opacity(0.92))
                    .frame(height: 5)
                    .shadow(color: BolaTheme.accent.opacity(index <= currentIndex ? 0.28 : 0), radius: 8, x: 0, y: 2)
            }
        }
    }
}

private struct OnboardingScreen<Content: View>: View {
    @ViewBuilder let content: Content
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    init(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
            }

            VStack(spacing: 10) {
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.35))
                }

                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BolaTheme.onAccentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(BolaTheme.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 18)
        }
    }
}

private struct WelcomeLoginPage: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 46)

            VStack(spacing: 16) {
                Text("欢迎来到")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.black)

                Text("BolaBola")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.black)

                Text("一个会陪你一起生活成长的\n手表宠物")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.top, 6)
            }

            Spacer(minLength: 18)

            HeroHalfDome {
                Image("bola手拿玫瑰")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 238)
                    .offset(x: -6, y: 16)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 30)

            Image(systemName: "apple.logo")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.black)

            Text("欢迎来到BolaBola")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.black)
                .padding(.top, 10)

            Text("和 Bola 一起让每一天变得更好吧！")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.34))
                .padding(.top, 4)

            Button(action: onContinue) {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20, weight: .bold))
                    Text("使用 Apple 继续")
                        .font(.system(size: 18, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 10))
                Text("点击登录即表示你同意《用户协议》和《隐私政策》。")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.35))
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }
}

private struct IntroCompanionPage: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Hi!")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(BolaTheme.accent.opacity(0.82))
                    .padding(.top, 18)

                Text("我是 Bola")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.top, 8)

                Text("我来自一个和你有点不一样的世界。\n现在，我会陪在你身边。\n如果你愿意，我会一点点了解你。")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.black.opacity(0.9))
                    .lineSpacing(5)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 18) {
                    IntroFeatureRow(
                        symbol: "heart.text.square.fill",
                        title: "我会陪伴你",
                        detail: "和你互动，慢慢熟悉，记住你的喜好"
                    )
                    IntroFeatureRow(
                        symbol: "sparkles.rectangle.stack.fill",
                        title: "我会慢慢成长",
                        detail: "每次陪伴都会让我变得不一样"
                    )
                    IntroFeatureRow(
                        symbol: "note.text",
                        title: "我会记住关于你的一切",
                        detail: "一起生活的那些日常，都会成为我们的记忆"
                    )
                }
                .padding(.top, 28)

                HStack {
                    Spacer()
                    Image("sticker_gathxr")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180)
                        .padding(.top, 18)
                    Spacer()
                }
                .padding(.bottom, 12)
            }
        }
    }
}

private struct LevelUpPage: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("多和 Bola 互动来提升")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 58)

                ZStack {
                    VStack(spacing: -8) {
                        Image("LevelUpHero")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 245)
                        Text("LEVEL UP!")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.98, green: 0.79, blue: 0.33))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 20) {
                    MetricExplainRow(
                        symbol: "arrow.up.right",
                        title: "成长值",
                        detail: "通过完成任务和日常互动获得，用于提升 Bola 的成长等级。"
                    )
                    MetricExplainRow(
                        symbol: "heart",
                        title: "陪伴值",
                        detail: "平时与 Bola 的陪伴时间越长，数值越高。"
                    )
                }
                .padding(.top, 8)

                GrowingBars()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
    }
}

private struct NotificationPermissionPage: View {
    let status: UNAuthorizationStatus
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingScreen(
            primaryTitle: status == .authorized ? "继续" : "允许通知",
            primaryAction: onAllow,
            secondaryTitle: "跳过",
            secondaryAction: onSkip
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让 Bola 更好的陪伴你")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 58)

                Text("允许 BolaBola 发送通知，更好的了解你的健康数据")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.34))
                    .padding(.top, 12)

                NotificationPlaceholderCard()
                    .padding(.top, 34)

                HStack {
                    Spacer()
                    Image("sticker_gathxr")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 196)
                    Spacer()
                }
                .padding(.top, 26)
            }
        }
    }
}

private struct HealthRhythmPage: View {
    let requested: Bool
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(
            primaryTitle: requested ? "继续" : "继续",
            primaryAction: onContinue
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bola 正在感知你的状态")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 38)

                Text("通过 HRV（心率变异性），Bola 会感知你现在的状态")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.34))
                    .padding(.top, 12)

                RhythmArcShowcase()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)

                RhythmLegendGrid()
                    .padding(.top, 26)
            }
        }
    }
}

private struct QuestionIntroPage: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("最后\n还有一些简单的问题")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .lineSpacing(6)
                    .padding(.top, 26)

                HStack {
                    Spacer()
                    QuestionBoxHero()
                        .frame(width: 220, height: 250)
                        .padding(.top, 56)
                    Spacer()
                }
            }
        }
    }
}

private struct UserNicknamePage: View {
    @Binding var nickname: String
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让我更了解一下你吧")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 24)

                HStack(alignment: .center) {
                    Text("我该如何称呼你呢")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black.opacity(0.92))
                    Spacer()
                    Image("sticker_gathxr")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 146)
                }
                .padding(.top, 34)

                RoundedTextField(text: $nickname, placeholder: "输入你的名字或昵称")
                    .padding(.top, 98)
            }
        }
    }
}

private struct BirthdayPage: View {
    @Binding var birthDate: Date
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让我更了解一下你吧")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 24)

                HStack(alignment: .center) {
                    Text("请问你的生日是？")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black.opacity(0.92))
                    Spacer()
                    Image("sticker_gathxr")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 146)
                }
                .padding(.top, 34)

                BirthdayPickerCard(birthDate: $birthDate)
                    .padding(.top, 56)
            }
        }
    }
}

private struct GenderPage: View {
    @Binding var selectedGender: OnboardingGender?
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让我更了解一下你吧")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 24)

                HStack(alignment: .center) {
                    Text("请问你的性别是？")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black.opacity(0.92))
                    Spacer()
                    Image("sticker_gathxr")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 146)
                }
                .padding(.top, 34)

                VStack(spacing: 14) {
                    ForEach(OnboardingGender.allCases) { option in
                        Button {
                            selectedGender = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.88))
                                Spacer()
                                if selectedGender == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(BolaTheme.accent)
                                }
                            }
                            .padding(.horizontal, 24)
                            .frame(height: 60)
                            .background(Color.white.opacity(selectedGender == option ? 0.96 : 0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                    }
                }
                .padding(.top, 94)
            }
        }
    }
}

private struct BolaNicknamePage: View {
    @Binding var nickname: String
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("给 Bola 起个专属名称吧")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 60)

                Text("它会记住这个名字哦")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .padding(.top, 14)

                ClearableRoundedField(text: $nickname, placeholder: "比如：波拉 / 小黑 / Bobo")
                    .padding(.top, 44)

                HStack {
                    Spacer()
                    GlowingMascotCard()
                        .frame(width: 260, height: 230)
                        .padding(.top, 58)
                    Spacer()
                }
            }
        }
    }
}

private struct ReadyPage: View {
    let onEnter: () -> Void

    var body: some View {
        OnboardingScreen(primaryTitle: "进入 Bola 的空间", primaryAction: onEnter) {
            VStack(alignment: .leading, spacing: 0) {
                Text("一切准备就绪！")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.top, 88)

                HStack {
                    Spacer()
                    ReadyHeroScene()
                        .frame(width: 320, height: 300)
                        .padding(.top, 66)
                    Spacer()
                }
            }
        }
    }
}

private struct IntroFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(BolaTheme.accent.opacity(0.88))
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
        }
    }
}

private struct MetricExplainRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(BolaTheme.accent)
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.black)
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GrowingBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach([0.48, 0.68, 0.86], id: \.self) { value in
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BolaTheme.accent.opacity(0.06), BolaTheme.accent.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 82, height: 220 * value)
            }
        }
        .frame(height: 220, alignment: .bottom)
    }
}

private struct NotificationPlaceholderCard: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .frame(height: 72)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 290, height: 34)
                .offset(y: -10)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 250, height: 30)
                .offset(y: -16)
        }
    }
}

private struct RhythmArcShowcase: View {
    var body: some View {
        ZStack {
            ArcShape()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.98, green: 0.61, blue: 0.12),
                            Color(red: 1.0, green: 0.87, blue: 0.12),
                            Color(red: 0.58, green: 0.95, blue: 0.32),
                            Color(red: 0.42, green: 0.9, blue: 0.75)
                        ],
                        center: .center,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0)
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 330, height: 180)

            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .offset(y: -78)

            VStack(spacing: -8) {
                ZStack {
                    Image("GrowthHeroIsland")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 170)
                    Image("sticker_gathxr")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92)
                        .offset(x: -14, y: -18)
                }
            }
            .offset(y: 42)
        }
    }
}

private struct RhythmLegendGrid: View {
    private let items: [(Color, String)] = [
        (Color(red: 0.42, green: 0.9, blue: 0.75), "节奏满满"),
        (Color(red: 0.58, green: 0.95, blue: 0.32), "节奏平稳"),
        (Color(red: 1.0, green: 0.87, blue: 0.12), "节奏起伏"),
        (Color(red: 0.98, green: 0.61, blue: 0.12), "节奏不稳"),
    ]

    var body: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 20) {
            ForEach(items, id: \.1) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.0)
                        .frame(width: 20, height: 20)
                    Text(item.1)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.56))
                }
            }
        }
    }
}

private struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

private struct QuestionBoxHero: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.78, green: 0.83, blue: 0.08), BolaTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: BolaTheme.accent.opacity(0.3), radius: 28, x: 0, y: 18)
                .frame(width: 126, height: 126)
                .overlay {
                    Text("?")
                        .font(.system(size: 86, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
                }

            Image("sticker_gathxr")
                .resizable()
                .scaledToFit()
                .frame(width: 80)
                .offset(y: -2)

            Text("?")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(BolaTheme.accent)
                .offset(x: 74, y: -54)

            Text("?")
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(BolaTheme.accent)
                .offset(x: 102, y: -30)
        }
    }
}

private struct RoundedTextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .frame(height: 60)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
    }
}

private struct BirthdayPickerCard: View {
    @Binding var birthDate: Date

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("", selection: $birthDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 190)

            Rectangle()
                .fill(Color.white.opacity(0.92))
                .frame(height: 34)
                .overlay {
                    Text(formattedDate)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.46))
                }
        }
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: birthDate)
    }
}

private struct ClearableRoundedField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.black)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.black.opacity(0.2))
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(Color.white.opacity(0.88))
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

private struct GlowingMascotCard: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BolaTheme.accent.opacity(0.85), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 106
                    )
                )
                .frame(width: 220, height: 220)
            Image("sticker_gathxr")
                .resizable()
                .scaledToFit()
                .frame(width: 188)
        }
    }
}

private struct ReadyHeroScene: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BolaTheme.accent.opacity(0.52), Color.clear],
                        center: .center,
                        startRadius: 24,
                        endRadius: 150
                    )
                )
                .frame(width: 280, height: 280)

            Image("WatchS10Full")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .offset(x: -88, y: 18)

            TriangleBeam()
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.35), BolaTheme.accent.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 160, height: 130)
                .rotationEffect(.degrees(-10))
                .offset(x: -12, y: 2)

            Image("sticker_gathxr")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .offset(x: 84, y: 0)
        }
    }
}

private struct TriangleBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HeroHalfDome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            HalfCircle()
                .fill(
                    LinearGradient(
                        colors: [
                            BolaTheme.accent.opacity(0.12),
                            BolaTheme.accent.opacity(0.42)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    ZStack {
                        sparkle(offsetX: -96, offsetY: 58, size: 18)
                        sparkle(offsetX: -24, offsetY: 24, size: 14)
                        sparkle(offsetX: 82, offsetY: 62, size: 16)
                        sparkle(offsetX: 132, offsetY: 76, size: 26)
                    }
                }

            content
        }
        .frame(height: 270)
    }

    private func sparkle(offsetX: CGFloat, offsetY: CGFloat, size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: offsetX, y: offsetY)
    }
}

private struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
