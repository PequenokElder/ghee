import SwiftUI

/// Funny one-liners that react to the knob you're turning.
final class QuipBoard: ObservableObject {
    @Published private(set) var line = "Drag a knob. Make it spreadable."
    let tagline = QuipBoard.taglines.randomElement()!
    private var lastKey = ""

    static let taglines = [
        "clarified guitar", "spreadable tone", "lightly salted", "now with 82% milkfat",
        "it's not margarine", "cultured, not corporate", "churned, not synthesized", "tone you can taste",
    ]

    // [low, middle, high] pools per knob.
    private static let lines: [String: [[String]]] = [
        "Churn": [
            ["Barely churning. It's still just cream out here.", "A gentle stir. Butter is a long game."],
            ["Steady churn. Your arms are getting tired.", "Good churning rhythm. Grandma approves."],
            ["Over-churned! You've made butter AND thunder.", "Churning so hard the cow is concerned."]],
        "Soften": [
            ["Cold butter: hard, dynamic, unforgiving.", "Straight from the fridge. Good luck spreading that."],
            ["Room temperature. Spreadable on toast.", "Perfectly softened. Dinner rolls are nervous."],
            ["Fully softened. Every note spreads evenly.", "So smooth even the loud parts got politely quiet."]],
        "Brown Butter": [
            ["Clean as unsalted sweet cream.", "Pure and innocent. Not a toasted milk solid in sight."],
            ["Getting nutty. Smells like a good riff.", "Beurre noisette achieved. Chefs are weeping."],
            ["Burnt! Beurre noir! Smoke alarm tone.", "That's not brown butter, that's a crime scene."]],
        "Stick": [
            ["Where did the stick go? That's a butter curl.", "Thin as the foil wrapper."],
            ["A respectable quarter-pound of low end.", "One solid stick. Pleasantly heavy."],
            ["A whole pound of low end. Your speakers need a doctor.", "So much bass the dish is sagging."]],
        "Spread": [
            ["Scooped mids, like a hollowed-out butter dish.", "The middle's gone. Someone ate it."],
            ["Even spread, edge to edge.", "No bare corners. Professional toast."],
            ["Thick layer! You can't see the toast.", "Mids everywhere. Carb-loaded."]],
        "Sizzle": [
            ["The pan's cold. No sizzle.", "Pale and quiet. Turn up the heat."],
            ["Gentle sizzle. The pan is just right.", "Golden edges. Eggs are on their way."],
            ["Crackling hot! Splatter warning.", "Sizzling so loud the neighbors smelled it."]],
        "Swirl": [
            ["A single stroke of the knife. Barely a swirl.", "Butter, unswirled. Very flat, very honest."],
            ["Lovely swirl. Like a pat on warm pancakes.", "Gently whipped. Light and wobbly."],
            ["Whipped into oblivion. This butter is seasick.", "So much swirl your guitar has a twin and they're fighting."]],
        "Melt": [
            ["Dry as a stick.", "Not a drop of melt. Very solid."],
            ["Puddling nicely in the cast iron.", "A warm, glossy pool of reverb."],
            ["Fully melted. You are a puddle in a cathedral.", "Past a pat, past a pool, now it's a lake."]],
        "Slather": [
            ["A scrape. Barely buttered.", "Whisper-thin. Diet toast."],
            ["Generous slather. Right on.", "Just enough to reach the crust."],
            ["Butter on butter on butter. Neighbors notified.", "Slathered beyond reason. Excellent."]],
    ]

    func say(_ knob: String, normalized n: Double) {
        guard let pools = Self.lines[knob] else { return }
        let bucket = n < 0.2 ? 0 : n > 0.8 ? 2 : 1
        let key = "\(knob)\(bucket)"
        guard key != lastKey else { return }
        lastKey = key
        line = pools[bucket].randomElement() ?? line
    }
}
