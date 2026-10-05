/// Ported question bank from src/data/dailyQuestions.js.
/// INVARIANT: Shuffled batches are append-only. Never edit or reorder an existing batch.
library;

class DailyQuestionItem {
  final String id;
  final String tone; // 'light' | 'memory' | 'deep' | 'future' | 'apart'
  final String text;

  const DailyQuestionItem({
    required this.id,
    required this.tone,
    required this.text,
  });
}

class QuestionBatch {
  final String id;
  final List<DailyQuestionItem> questions;

  const QuestionBatch({required this.id, required this.questions});
}

const List<DailyQuestionItem> batchOne = [
  /* ---------------------------------------------------------------- light */
  DailyQuestionItem(id: 'b1-001', tone: 'light', text: 'What is the most useless thing you know a lot about?'),
  DailyQuestionItem(id: 'b1-002', tone: 'light', text: 'If you had to describe me to a stranger using only three words, which three?'),
  DailyQuestionItem(id: 'b1-003', tone: 'light', text: 'What food would you happily eat every single day for a year?'),
  DailyQuestionItem(id: 'b1-004', tone: 'light', text: 'What is something everyone seems to love that you quietly do not?'),
  DailyQuestionItem(id: 'b1-005', tone: 'light', text: 'What song have you had on repeat lately, and be honest about how many times.'),
  DailyQuestionItem(id: 'b1-006', tone: 'light', text: 'If we had to enter a competition together tomorrow, what should it be?'),
  DailyQuestionItem(id: 'b1-007', tone: 'light', text: 'What is the pettiest thing you have ever held a grudge about?'),
  DailyQuestionItem(id: 'b1-008', tone: 'light', text: 'What would the title of a documentary about your week be?'),
  DailyQuestionItem(id: 'b1-009', tone: 'light', text: 'What is a compliment you have received that you still think about?'),
  DailyQuestionItem(id: 'b1-010', tone: 'light', text: 'What is something you are weirdly good at that never comes up?'),
  DailyQuestionItem(id: 'b1-011', tone: 'light', text: 'If you could instantly master one skill tonight, what are you picking?'),
  DailyQuestionItem(id: 'b1-012', tone: 'light', text: 'What is the last thing that made you laugh out loud, alone?'),
  DailyQuestionItem(id: 'b1-013', tone: 'light', text: 'What is your most irrational fear?'),
  DailyQuestionItem(id: 'b1-014', tone: 'light', text: 'What would you spend an unexpected free day doing, with no one watching?'),
  DailyQuestionItem(id: 'b1-015', tone: 'light', text: 'What is something small that instantly improves your mood?'),
  DailyQuestionItem(id: 'b1-016', tone: 'light', text: 'Which fictional character do you think I am most like?'),
  DailyQuestionItem(id: 'b1-017', tone: 'light', text: 'What is the worst haircut or outfit you have ever committed to?'),
  DailyQuestionItem(id: 'b1-018', tone: 'light', text: 'What is an opinion of yours that most people argue with?'),
  DailyQuestionItem(id: 'b1-019', tone: 'light', text: 'What is the best thing you have eaten in the last month?'),
  DailyQuestionItem(id: 'b1-020', tone: 'light', text: 'If our relationship had a theme song, what would you pick and why?'),
  DailyQuestionItem(id: 'b1-021', tone: 'light', text: 'What is something you pretend to understand but genuinely do not?'),
  DailyQuestionItem(id: 'b1-022', tone: 'light', text: 'What would you want your last meal to be, if you had to decide today?'),
  DailyQuestionItem(id: 'b1-023', tone: 'light', text: 'What is a rule you follow that nobody asked you to follow?'),
  DailyQuestionItem(id: 'b1-024', tone: 'light', text: 'What is the most embarrassing thing in your search history this week?'),
  DailyQuestionItem(id: 'b1-025', tone: 'light', text: 'If you had to give up one sense to keep another sharper, how would you trade?'),
  DailyQuestionItem(id: 'b1-026', tone: 'light', text: 'What is something you own that you would be genuinely sad to lose?'),
  DailyQuestionItem(id: 'b1-027', tone: 'light', text: 'What is a habit of mine you find funny?'),
  DailyQuestionItem(id: 'b1-028', tone: 'light', text: 'What is the strangest dream you remember having?'),
  DailyQuestionItem(id: 'b1-029', tone: 'light', text: 'If you could send one message to yourself five years ago, what would it say?'),
  DailyQuestionItem(id: 'b1-030', tone: 'light', text: 'What is something you would do if you knew nobody would judge you for it?'),
  DailyQuestionItem(id: 'b1-031', tone: 'light', text: 'What is your comfort film, book or show, the one you return to?'),
  DailyQuestionItem(id: 'b1-032', tone: 'light', text: 'What is a small luxury you think is completely worth the money?'),
  DailyQuestionItem(id: 'b1-033', tone: 'light', text: 'What animal do you think you would be, and do not pick a flattering one.'),
  DailyQuestionItem(id: 'b1-034', tone: 'light', text: 'What is the nicest thing a stranger has ever done for you?'),
  DailyQuestionItem(id: 'b1-035', tone: 'light', text: 'What is something you are looking forward to this week, however small?'),
  DailyQuestionItem(id: 'b1-036', tone: 'light', text: 'What is a word or phrase you use far too often?'),

  /* --------------------------------------------------------------- memory */
  DailyQuestionItem(id: 'b1-037', tone: 'memory', text: 'What do you actually remember about the first time we spoke?'),
  DailyQuestionItem(id: 'b1-038', tone: 'memory', text: 'What did you think of me before you knew me properly?'),
  DailyQuestionItem(id: 'b1-039', tone: 'memory', text: 'What is a message from me you have gone back and read again?'),
  DailyQuestionItem(id: 'b1-040', tone: 'memory', text: 'When did you first realise this was going somewhere?'),
  DailyQuestionItem(id: 'b1-041', tone: 'memory', text: 'What is something I said early on that you have not forgotten?'),
  DailyQuestionItem(id: 'b1-042', tone: 'memory', text: 'What was happening in your life when we first started talking?'),
  DailyQuestionItem(id: 'b1-043', tone: 'memory', text: 'What is a conversation of ours you wish you could listen to again?'),
  DailyQuestionItem(id: 'b1-044', tone: 'memory', text: 'When did you last feel proud of me?'),
  DailyQuestionItem(id: 'b1-045', tone: 'memory', text: 'What is the first thing you noticed about how I talk?'),
  DailyQuestionItem(id: 'b1-046', tone: 'memory', text: 'What is a day with me that you would happily relive exactly as it was?'),
  DailyQuestionItem(id: 'b1-047', tone: 'memory', text: 'What did you assume about me that turned out to be completely wrong?'),
  DailyQuestionItem(id: 'b1-048', tone: 'memory', text: 'What is the funniest misunderstanding we have ever had?'),
  DailyQuestionItem(id: 'b1-049', tone: 'memory', text: 'When were you most nervous talking to me, and why?'),
  DailyQuestionItem(id: 'b1-050', tone: 'memory', text: 'What is something I did that mattered more than I probably realised?'),
  DailyQuestionItem(id: 'b1-051', tone: 'memory', text: 'What is a version of me you have seen that nobody else has?'),
  DailyQuestionItem(id: 'b1-052', tone: 'memory', text: 'What was the moment you stopped worrying about how you sounded around me?'),
  DailyQuestionItem(id: 'b1-053', tone: 'memory', text: 'What is a photo of us, or of me, that you keep coming back to?'),
  DailyQuestionItem(id: 'b1-054', tone: 'memory', text: 'What is the first thing you ever told someone else about me?'),
  DailyQuestionItem(id: 'b1-055', tone: 'memory', text: 'What did you hope for from this, back at the beginning?'),
  DailyQuestionItem(id: 'b1-056', tone: 'memory', text: 'What is something you were scared to tell me that turned out fine?'),
  DailyQuestionItem(id: 'b1-057', tone: 'memory', text: 'When did I last surprise you?'),
  DailyQuestionItem(id: 'b1-058', tone: 'memory', text: 'What is a small thing I have said that you now say too?'),
  DailyQuestionItem(id: 'b1-059', tone: 'memory', text: 'What is the longest we have gone without speaking, and how was that?'),
  DailyQuestionItem(id: 'b1-060', tone: 'memory', text: 'What is something about the way we started that you would not change?'),
  DailyQuestionItem(id: 'b1-061', tone: 'memory', text: 'What is a moment where you nearly said something and did not?'),
  DailyQuestionItem(id: 'b1-062', tone: 'memory', text: 'What has been the best day of this year for you so far?'),
  DailyQuestionItem(id: 'b1-063', tone: 'memory', text: 'What did you use to be embarrassed about that you are not any more?'),
  DailyQuestionItem(id: 'b1-064', tone: 'memory', text: 'What is a compliment I gave you that you did not believe at the time?'),
  DailyQuestionItem(id: 'b1-065', tone: 'memory', text: 'When did you first tell someone you were serious about me?'),
  DailyQuestionItem(id: 'b1-066', tone: 'memory', text: 'What is something we did early on that we should start doing again?'),

  /* ----------------------------------------------------------------- deep */
  DailyQuestionItem(id: 'b1-067', tone: 'deep', text: 'What is something you want me to understand about you but struggle to explain?'),
  DailyQuestionItem(id: 'b1-068', tone: 'deep', text: 'What do you think I underestimate about myself?'),
  DailyQuestionItem(id: 'b1-069', tone: 'deep', text: 'What is something you are afraid of that you have never said out loud?'),
  DailyQuestionItem(id: 'b1-070', tone: 'deep', text: 'When do you feel most like yourself?'),
  DailyQuestionItem(id: 'b1-071', tone: 'deep', text: 'What is a way you have changed in the last year that you are glad about?'),
  DailyQuestionItem(id: 'b1-072', tone: 'deep', text: 'What do you need from me that you have never actually asked for?'),
  DailyQuestionItem(id: 'b1-073', tone: 'deep', text: 'What is the hardest thing you have forgiven someone for?'),
  DailyQuestionItem(id: 'b1-074', tone: 'deep', text: 'What part of yourself are you still working on?'),
  DailyQuestionItem(id: 'b1-075', tone: 'deep', text: 'What does feeling safe with someone look like, concretely, for you?'),
  DailyQuestionItem(id: 'b1-076', tone: 'deep', text: 'What is something you believe now that you would have argued with at eighteen?'),
  DailyQuestionItem(id: 'b1-077', tone: 'deep', text: 'When was the last time you cried, and would you tell me about it?'),
  DailyQuestionItem(id: 'b1-078', tone: 'deep', text: 'What is a compliment you wish people gave you more often?'),
  DailyQuestionItem(id: 'b1-079', tone: 'deep', text: 'What do you do when you are struggling and do not want to say so?'),
  DailyQuestionItem(id: 'b1-080', tone: 'deep', text: 'What is something about your family that shaped you more than you would like?'),
  DailyQuestionItem(id: 'b1-081', tone: 'deep', text: 'What does love look like to you when nothing dramatic is happening?'),
  DailyQuestionItem(id: 'b1-082', tone: 'deep', text: 'What is a mistake you made that you are quietly grateful for?'),
  DailyQuestionItem(id: 'b1-083', tone: 'deep', text: 'What do you find hardest to believe when I say it about you?'),
  DailyQuestionItem(id: 'b1-084', tone: 'deep', text: 'What is something you are carrying right now that you have not put down?'),
  DailyQuestionItem(id: 'b1-085', tone: 'deep', text: 'When do you feel most distant from me, even when nothing is wrong?'),
  DailyQuestionItem(id: 'b1-086', tone: 'deep', text: 'What is a boundary you wish you were better at holding?'),
  DailyQuestionItem(id: 'b1-087', tone: 'deep', text: 'What would you want said about you by the people who know you best?'),
  DailyQuestionItem(id: 'b1-088', tone: 'deep', text: 'What is something you have never been able to be honest about with anyone?'),
  DailyQuestionItem(id: 'b1-089', tone: 'deep', text: 'What is the kindest thing you have done that nobody knows about?'),
  DailyQuestionItem(id: 'b1-090', tone: 'deep', text: 'What makes you feel genuinely chosen?'),
  DailyQuestionItem(id: 'b1-091', tone: 'deep', text: 'What is a fear you have about us, even a small one?'),
  DailyQuestionItem(id: 'b1-092', tone: 'deep', text: 'What do you think you are like to love?'),
  DailyQuestionItem(id: 'b1-093', tone: 'deep', text: 'When did you last feel lonely, and what would have helped?'),
  DailyQuestionItem(id: 'b1-094', tone: 'deep', text: 'What is something you have outgrown but still catch yourself doing?'),
  DailyQuestionItem(id: 'b1-095', tone: 'deep', text: 'What do you want to be true about you in ten years that is not yet?'),
  DailyQuestionItem(id: 'b1-096', tone: 'deep', text: 'What is the difference between how you seem and how you actually are?'),
  DailyQuestionItem(id: 'b1-097', tone: 'deep', text: 'What is something you would want me to do if you went quiet for a while?'),
  DailyQuestionItem(id: 'b1-098', tone: 'deep', text: 'What has been the loneliest period of your life, and what got you through?'),
  DailyQuestionItem(id: 'b1-099', tone: 'deep', text: 'What do you think is the most misunderstood thing about you?'),
  DailyQuestionItem(id: 'b1-100', tone: 'deep', text: 'What is something I do that makes you feel looked after?'),
  DailyQuestionItem(id: 'b1-101', tone: 'deep', text: 'What would you like to be braver about?'),
  DailyQuestionItem(id: 'b1-102', tone: 'deep', text: 'What is something you have never asked me but have wondered about?'),

  /* --------------------------------------------------------------- future */
  DailyQuestionItem(id: 'b1-103', tone: 'future', text: 'What is the first thing you want to do when we are finally in the same place?'),
  DailyQuestionItem(id: 'b1-104', tone: 'future', text: 'What does an ordinary Tuesday with me look like, in your head?'),
  DailyQuestionItem(id: 'b1-105', tone: 'future', text: 'What is something you want us to be better at?'),
  DailyQuestionItem(id: 'b1-106', tone: 'future', text: 'Where do you want to wake up on your fortieth birthday?'),
  DailyQuestionItem(id: 'b1-107', tone: 'future', text: 'What is a tradition you want us to have that we do not have yet?'),
  DailyQuestionItem(id: 'b1-108', tone: 'future', text: 'What kind of home do you want, not the house, the feeling of it?'),
  DailyQuestionItem(id: 'b1-109', tone: 'future', text: 'What is something you want to learn, and would you want me learning it too?'),
  DailyQuestionItem(id: 'b1-110', tone: 'future', text: 'What do you want more of in your life in six months?'),
  DailyQuestionItem(id: 'b1-111', tone: 'future', text: 'What is a trip you want to take that has nothing to do with the destination?'),
  DailyQuestionItem(id: 'b1-112', tone: 'future', text: 'What do you hope has not changed about us in ten years?'),
  DailyQuestionItem(id: 'b1-113', tone: 'future', text: 'What is a goal of yours I could actually help with?'),
  DailyQuestionItem(id: 'b1-114', tone: 'future', text: 'What does a good argument between us look like?'),
  DailyQuestionItem(id: 'b1-115', tone: 'future', text: 'What is something you want to stop putting off?'),
  DailyQuestionItem(id: 'b1-116', tone: 'future', text: 'How do you want to be looked after when you are ill or exhausted?'),
  DailyQuestionItem(id: 'b1-117', tone: 'future', text: 'What is a version of your life you have quietly given up on, and should you have?'),
  DailyQuestionItem(id: 'b1-118', tone: 'future', text: 'What would you want our first shared space to have in it?'),
  DailyQuestionItem(id: 'b1-119', tone: 'future', text: 'What is something you want to do together that most couples would find boring?'),
  DailyQuestionItem(id: 'b1-120', tone: 'future', text: 'What do you want to be known for?'),
  DailyQuestionItem(id: 'b1-121', tone: 'future', text: 'What is a promise you would like us to make and actually keep?'),
  DailyQuestionItem(id: 'b1-122', tone: 'future', text: 'What is something you want me to remind you of when you forget it?'),
  DailyQuestionItem(id: 'b1-123', tone: 'future', text: 'What does supporting each other look like when one of us is failing at something?'),
  DailyQuestionItem(id: 'b1-124', tone: 'future', text: 'What is a small thing you want to start doing every day?'),
  DailyQuestionItem(id: 'b1-125', tone: 'future', text: 'What would you want a normal weekend with me to be like?'),
  DailyQuestionItem(id: 'b1-126', tone: 'future', text: 'What do you want to have said yes to by this time next year?'),
  DailyQuestionItem(id: 'b1-127', tone: 'future', text: 'What is something about the future that genuinely excites you?'),
  DailyQuestionItem(id: 'b1-128', tone: 'future', text: 'What would make you feel most secure about where this is going?'),
  DailyQuestionItem(id: 'b1-129', tone: 'future', text: 'What is a hard conversation we will need to have eventually?'),
  DailyQuestionItem(id: 'b1-130', tone: 'future', text: 'What do you want your relationship with your work to look like?'),
  DailyQuestionItem(id: 'b1-131', tone: 'future', text: 'What is something you would want us to do on a really bad day?'),
  DailyQuestionItem(id: 'b1-132', tone: 'future', text: 'What would you want me to have learned about you a year from now?'),
  DailyQuestionItem(id: 'b1-133', tone: 'future', text: 'What is a place you want to show me, and what will you show me first?'),
  DailyQuestionItem(id: 'b1-134', tone: 'future', text: 'What kind of old person do you want to be?'),

  /* ---------------------------------------------------------------- apart */
  DailyQuestionItem(id: 'b1-135', tone: 'apart', text: 'What is the hardest part of the day when we are apart?'),
  DailyQuestionItem(id: 'b1-136', tone: 'apart', text: 'What do you miss that is not the obvious thing?'),
  DailyQuestionItem(id: 'b1-137', tone: 'apart', text: 'What is something you wanted to show me today but could not?'),
  DailyQuestionItem(id: 'b1-138', tone: 'apart', text: 'What does a good day apart look like, honestly?'),
  DailyQuestionItem(id: 'b1-139', tone: 'apart', text: 'What do you do when you miss me and cannot say so right then?'),
  DailyQuestionItem(id: 'b1-140', tone: 'apart', text: 'What is something about distance that has been unexpectedly good for us?'),
  DailyQuestionItem(id: 'b1-141', tone: 'apart', text: 'When during the day do you think about me without meaning to?'),
  DailyQuestionItem(id: 'b1-142', tone: 'apart', text: 'What would you want me to send you on a bad day, with no explanation?'),
  DailyQuestionItem(id: 'b1-143', tone: 'apart', text: 'What is a small thing I could do from here that would actually help?'),
  DailyQuestionItem(id: 'b1-144', tone: 'apart', text: 'What do you wish I could see about your day-to-day life?'),
  DailyQuestionItem(id: 'b1-145', tone: 'apart', text: 'What is the worst thing about explaining us to other people?'),
  DailyQuestionItem(id: 'b1-146', tone: 'apart', text: 'What do you find yourself saving up to tell me?'),
  DailyQuestionItem(id: 'b1-147', tone: 'apart', text: 'What is something you have learned about yourself from being apart?'),
  DailyQuestionItem(id: 'b1-148', tone: 'apart', text: 'What does your room look like right now, honestly, no tidying first?'),
  DailyQuestionItem(id: 'b1-149', tone: 'apart', text: 'What is something ordinary about your day you have never described to me?'),
  DailyQuestionItem(id: 'b1-150', tone: 'apart', text: 'When do you feel closest to me, despite everything?'),
  DailyQuestionItem(id: 'b1-151', tone: 'apart', text: 'What do you worry I do not know about your life here?'),
  DailyQuestionItem(id: 'b1-152', tone: 'apart', text: 'What is a sound or smell where you are that I would not recognise?'),
  DailyQuestionItem(id: 'b1-153', tone: 'apart', text: 'What is the last thing you thought about before sleeping last night?'),
  DailyQuestionItem(id: 'b1-154', tone: 'apart', text: 'What would you want to do together if we had exactly one hour, right now?'),
  DailyQuestionItem(id: 'b1-155', tone: 'apart', text: 'What is something you have stopped telling me because it felt too small?'),
  DailyQuestionItem(id: 'b1-156', tone: 'apart', text: 'Who in your life knows the most about me, and what have you told them?'),
  DailyQuestionItem(id: 'b1-157', tone: 'apart', text: 'What is the thing you most want me to be there for?'),
  DailyQuestionItem(id: 'b1-158', tone: 'apart', text: 'What do you do differently when you know we are about to talk?'),
  DailyQuestionItem(id: 'b1-159', tone: 'apart', text: 'What is something you have wanted to ask me but keep not asking?'),
  DailyQuestionItem(id: 'b1-160', tone: 'apart', text: 'What is a part of your day I would find boring but you would want me there for?'),
  DailyQuestionItem(id: 'b1-161', tone: 'apart', text: 'What does missing someone feel like, physically, for you?'),
  DailyQuestionItem(id: 'b1-162', tone: 'apart', text: 'What is something you are protecting me from knowing?'),
  DailyQuestionItem(id: 'b1-163', tone: 'apart', text: 'What would you want me to notice about you that a screen does not show?'),
  DailyQuestionItem(id: 'b1-164', tone: 'apart', text: 'What has this distance taught you that you would not have learned otherwise?'),
  DailyQuestionItem(id: 'b1-165', tone: 'apart', text: 'What is the first thing you check when you wake up, and be honest.'),
  DailyQuestionItem(id: 'b1-166', tone: 'apart', text: 'What is something you do that you would be embarrassed for me to walk in on?'),
  DailyQuestionItem(id: 'b1-167', tone: 'apart', text: 'What do you wish we could do at the same time, from where we each are?'),
  DailyQuestionItem(id: 'b1-168', tone: 'apart', text: 'What is a moment today you would have wanted me to see?'),
  DailyQuestionItem(id: 'b1-169', tone: 'apart', text: 'What is the hardest thing about not being able to just show up?'),
  DailyQuestionItem(id: 'b1-170', tone: 'apart', text: 'What would you want said to you tonight, in someone else’s words or mine?'),
  DailyQuestionItem(id: 'b1-171', tone: 'apart', text: 'What is something you have been putting off telling me?'),
  DailyQuestionItem(id: 'b1-172', tone: 'apart', text: 'What does home mean to you right now?'),
  DailyQuestionItem(id: 'b1-173', tone: 'apart', text: 'What is a way I could make an ordinary Wednesday feel like something?'),
  DailyQuestionItem(id: 'b1-174', tone: 'apart', text: 'What is the best thing anyone said to you this week?'),
  DailyQuestionItem(id: 'b1-175', tone: 'apart', text: 'What do you need more of from me lately?'),
  DailyQuestionItem(id: 'b1-176', tone: 'apart', text: 'What is something you would rather I asked you directly?'),
  DailyQuestionItem(id: 'b1-177', tone: 'apart', text: 'What is a small ritual of ours that you would miss if it stopped?'),
  DailyQuestionItem(id: 'b1-178', tone: 'apart', text: 'What is the kindest thing I have done from this far away?'),
  DailyQuestionItem(id: 'b1-179', tone: 'apart', text: 'What do you want me to know before you go to sleep tonight?'),
  DailyQuestionItem(id: 'b1-180', tone: 'apart', text: 'What has today actually been like, past the version you would normally give?'),
];

const List<QuestionBatch> questionBatches = [
  QuestionBatch(id: 'b1', questions: batchOne),
];

final List<DailyQuestionItem> allQuestions = questionBatches
    .expand((batch) => batch.questions)
    .toList(growable: false);

DailyQuestionItem? findQuestion(String id) {
  try {
    return allQuestions.firstWhere((q) => q.id == id);
  } catch (_) {
    return null;
  }
}
