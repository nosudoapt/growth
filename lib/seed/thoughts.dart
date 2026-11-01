/// Bundled thought bank — 30 entries, rotated without repeats for 30 days.
class Thought {
  const Thought(this.text, this.tag);
  final String text;
  final String tag;

  /// Count of words; used for the staggered word animation.
  List<String> get words => text.split(RegExp(r'\s+'));

  int sentenceCount() =>
      RegExp(r'[.!?]').allMatches(text).length == 0
          ? 1
          : RegExp(r'[.!?]').allMatches(text).length;
}

const List<Thought> kThoughtBank = [
  Thought('Anger is a fire you pay for while hoping someone else gets burned.', 'Stoic reflection'),
  Thought('Most arguments are two egos defending themselves. Ask which one you are protecting.', 'Psychology'),
  Thought('Socrates asked questions until others found what they did not know.', 'Socratic method'),
  Thought('Your attention is the one asset you cannot get back. Spend it like it is finite.', 'Naval Ravikant'),
  Thought('Invert the problem: list what would ruin a good life, then avoid those things.', 'Charlie Munger'),
  Thought('Nam Simran: remember the Divine in ordinary moments. Three slow breaths with awareness count.', 'Sikh practice'),
  Thought('Marcus Aurelius wrote that the obstacle is the way.', 'Meditations'),
  Thought('Icarus flew too high on borrowed wings. Watch for the moment success makes you feel special.', 'Greek myth'),
  Thought('Poor sleep makes anger louder and patience quieter.', 'Sleep science'),
  Thought('One honest small act a day, repeated, changes character.', 'Habit research'),
  Thought('You rise to the level of your systems, not your goals.', 'Atomic Habits'),
  Thought('Listen to understand, not to reply.', 'Communication'),
  Thought('Eudaimonia, flourishing, comes from virtue practiced daily.', 'Aristotle'),
  Thought('Gratitude interrupts anger. Name one thing you are thankful for.', 'Positive psychology'),
  Thought('Seek wealth, not money or status: assets that earn while you sleep.', 'Naval Ravikant'),
  Thought('We notice evidence that fits what we already believe. Argue the other side once a day.', 'Confirmation bias'),
  Thought('Sunk cost keeps you in things only because you have already paid.', 'Decision science'),
  Thought('A thought is not a fact. Ask what proves the one you are holding.', 'Cognitive therapy'),
  Thought('"Know thyself" was inscribed at Delphi. Most of life is that slow work.', 'Delphi'),
  Thought('Time is the currency you spend on everything. Spend one hour on what your future self needs.', 'Time management'),
  Thought('Anger often hides hurt. Ask what it is protecting.', 'Emotional intelligence'),
  Thought('Humility is thinking of yourself less often, not thinking less of yourself.', 'C. S. Lewis, paraphrased'),
  Thought('The Stoics reviewed their day each evening. Ten minutes beats a year of guessing.', 'Stoic practice'),
  Thought('Alexander wept with no worlds left to conquer. Chasing one goal can empty you.', 'Plutarch'),
  Thought('Picture the person you want to be tomorrow.', 'Napoleon, paraphrased'),
  Thought('The best victory is won before the battle starts.', 'Sun Tzu, The Art of War'),
  Thought('Decide the cost before you are in the moment.', 'Caesar and the Rubicon'),
  Thought('If it will not make you better or happier by tomorrow, it is not worth an hour.', 'Practical wisdom'),
  Thought('"As above, so below" suggests patterns repeat at every scale. Notice one this week.', 'Hermetic tradition, a thinking tool, not a fact'),
  Thought('Your phone is a slot machine on a schedule. Choose one action that is not a reaction.', 'Attention research'),
];
