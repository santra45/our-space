/**
 * src/data/dailyQuestions.js
 * The question bank.
 *
 * WHY THESE ARE WRITTEN RATHER THAN BORROWED
 * The well-known sets are not ours to ship. We're Not Really Strangers is a
 * copyrighted deck, the app banks are proprietary, and Aron's 36 questions come
 * from a paper. Beyond that, all of them are written for people in the same
 * room. These are written for two people who are not.
 *
 * WHAT IS DELIBERATELY ABSENT
 * Nothing assumes a shared physical past - no "remember that restaurant", no
 * "the first time you held my hand". A question that quietly assumes a history
 * the two people do not have is worse than no question, because it lands as a
 * small reminder of what is missing. Memory questions here are about
 * conversations, first impressions, and the things that happen over a phone.
 *
 * BATCHES ARE APPEND-ONLY
 * The day-to-question mapping is a shuffle of this bank. Adding questions to an
 * EXISTING batch would reshuffle the whole thing and start repeating ones
 * already answered. Adding a NEW batch appends to the end and disturbs nothing.
 * So: never edit or reorder a shipped batch. Add batch two.
 *
 * Tones are `light` | `memory` | `deep` | `future` | `apart`. Nothing reads
 * them yet; they are here so the balance of the bank is reviewable, and so a
 * future "keep it light today" filter has something to filter on.
 */

const q = (id, tone, text) => Object.freeze({ id, tone, text });

/**
 * Batch one. 180 questions - roughly six months of daily use.
 */
const BATCH_ONE = Object.freeze([
  /* ---------------------------------------------------------------- light */
  q('b1-001', 'light', 'What is the most useless thing you know a lot about?'),
  q('b1-002', 'light', 'If you had to describe me to a stranger using only three words, which three?'),
  q('b1-003', 'light', 'What food would you happily eat every single day for a year?'),
  q('b1-004', 'light', 'What is something everyone seems to love that you quietly do not?'),
  q('b1-005', 'light', 'What song have you had on repeat lately, and be honest about how many times.'),
  q('b1-006', 'light', 'If we had to enter a competition together tomorrow, what should it be?'),
  q('b1-007', 'light', 'What is the pettiest thing you have ever held a grudge about?'),
  q('b1-008', 'light', 'What would the title of a documentary about your week be?'),
  q('b1-009', 'light', 'What is a compliment you have received that you still think about?'),
  q('b1-010', 'light', 'What is something you are weirdly good at that never comes up?'),
  q('b1-011', 'light', 'If you could instantly master one skill tonight, what are you picking?'),
  q('b1-012', 'light', 'What is the last thing that made you laugh out loud, alone?'),
  q('b1-013', 'light', 'What is your most irrational fear?'),
  q('b1-014', 'light', 'What would you spend an unexpected free day doing, with no one watching?'),
  q('b1-015', 'light', 'What is something small that instantly improves your mood?'),
  q('b1-016', 'light', 'Which fictional character do you think I am most like?'),
  q('b1-017', 'light', 'What is the worst haircut or outfit you have ever committed to?'),
  q('b1-018', 'light', 'What is an opinion of yours that most people argue with?'),
  q('b1-019', 'light', 'What is the best thing you have eaten in the last month?'),
  q('b1-020', 'light', 'If our relationship had a theme song, what would you pick and why?'),
  q('b1-021', 'light', 'What is something you pretend to understand but genuinely do not?'),
  q('b1-022', 'light', 'What would you want your last meal to be, if you had to decide today?'),
  q('b1-023', 'light', 'What is a rule you follow that nobody asked you to follow?'),
  q('b1-024', 'light', 'What is the most embarrassing thing in your search history this week?'),
  q('b1-025', 'light', 'If you had to give up one sense to keep another sharper, how would you trade?'),
  q('b1-026', 'light', 'What is something you own that you would be genuinely sad to lose?'),
  q('b1-027', 'light', 'What is a habit of mine you find funny?'),
  q('b1-028', 'light', 'What is the strangest dream you remember having?'),
  q('b1-029', 'light', 'If you could send one message to yourself five years ago, what would it say?'),
  q('b1-030', 'light', 'What is something you would do if you knew nobody would judge you for it?'),
  q('b1-031', 'light', 'What is your comfort film, book or show, the one you return to?'),
  q('b1-032', 'light', 'What is a small luxury you think is completely worth the money?'),
  q('b1-033', 'light', 'What animal do you think you would be, and do not pick a flattering one.'),
  q('b1-034', 'light', 'What is the nicest thing a stranger has ever done for you?'),
  q('b1-035', 'light', 'What is something you are looking forward to this week, however small?'),
  q('b1-036', 'light', 'What is a word or phrase you use far too often?'),

  /* --------------------------------------------------------------- memory */
  q('b1-037', 'memory', 'What do you actually remember about the first time we spoke?'),
  q('b1-038', 'memory', 'What did you think of me before you knew me properly?'),
  q('b1-039', 'memory', 'What is a message from me you have gone back and read again?'),
  q('b1-040', 'memory', 'When did you first realise this was going somewhere?'),
  q('b1-041', 'memory', 'What is something I said early on that you have not forgotten?'),
  q('b1-042', 'memory', 'What was happening in your life when we first started talking?'),
  q('b1-043', 'memory', 'What is a conversation of ours you wish you could listen to again?'),
  q('b1-044', 'memory', 'When did you last feel proud of me?'),
  q('b1-045', 'memory', 'What is the first thing you noticed about how I talk?'),
  q('b1-046', 'memory', 'What is a day with me that you would happily relive exactly as it was?'),
  q('b1-047', 'memory', 'What did you assume about me that turned out to be completely wrong?'),
  q('b1-048', 'memory', 'What is the funniest misunderstanding we have ever had?'),
  q('b1-049', 'memory', 'When were you most nervous talking to me, and why?'),
  q('b1-050', 'memory', 'What is something I did that mattered more than I probably realised?'),
  q('b1-051', 'memory', 'What is a version of me you have seen that nobody else has?'),
  q('b1-052', 'memory', 'What was the moment you stopped worrying about how you sounded around me?'),
  q('b1-053', 'memory', 'What is a photo of us, or of me, that you keep coming back to?'),
  q('b1-054', 'memory', 'What is the first thing you ever told someone else about me?'),
  q('b1-055', 'memory', 'What did you hope for from this, back at the beginning?'),
  q('b1-056', 'memory', 'What is something you were scared to tell me that turned out fine?'),
  q('b1-057', 'memory', 'When did I last surprise you?'),
  q('b1-058', 'memory', 'What is a small thing I have said that you now say too?'),
  q('b1-059', 'memory', 'What is the longest we have gone without speaking, and how was that?'),
  q('b1-060', 'memory', 'What is something about the way we started that you would not change?'),
  q('b1-061', 'memory', 'What is a moment where you nearly said something and did not?'),
  q('b1-062', 'memory', 'What has been the best day of this year for you so far?'),
  q('b1-063', 'memory', 'What did you use to be embarrassed about that you are not any more?'),
  q('b1-064', 'memory', 'What is a compliment I gave you that you did not believe at the time?'),
  q('b1-065', 'memory', 'When did you first tell someone you were serious about me?'),
  q('b1-066', 'memory', 'What is something we did early on that we should start doing again?'),

  /* ----------------------------------------------------------------- deep */
  q('b1-067', 'deep', 'What is something you want me to understand about you but struggle to explain?'),
  q('b1-068', 'deep', 'What do you think I underestimate about myself?'),
  q('b1-069', 'deep', 'What is something you are afraid of that you have never said out loud?'),
  q('b1-070', 'deep', 'When do you feel most like yourself?'),
  q('b1-071', 'deep', 'What is a way you have changed in the last year that you are glad about?'),
  q('b1-072', 'deep', 'What do you need from me that you have never actually asked for?'),
  q('b1-073', 'deep', 'What is the hardest thing you have forgiven someone for?'),
  q('b1-074', 'deep', 'What part of yourself are you still working on?'),
  q('b1-075', 'deep', 'What does feeling safe with someone look like, concretely, for you?'),
  q('b1-076', 'deep', 'What is something you believe now that you would have argued with at eighteen?'),
  q('b1-077', 'deep', 'When was the last time you cried, and would you tell me about it?'),
  q('b1-078', 'deep', 'What is a compliment you wish people gave you more often?'),
  q('b1-079', 'deep', 'What do you do when you are struggling and do not want to say so?'),
  q('b1-080', 'deep', 'What is something about your family that shaped you more than you would like?'),
  q('b1-081', 'deep', 'What does love look like to you when nothing dramatic is happening?'),
  q('b1-082', 'deep', 'What is a mistake you made that you are quietly grateful for?'),
  q('b1-083', 'deep', 'What do you find hardest to believe when I say it about you?'),
  q('b1-084', 'deep', 'What is something you are carrying right now that you have not put down?'),
  q('b1-085', 'deep', 'When do you feel most distant from me, even when nothing is wrong?'),
  q('b1-086', 'deep', 'What is a boundary you wish you were better at holding?'),
  q('b1-087', 'deep', 'What would you want said about you by the people who know you best?'),
  q('b1-088', 'deep', 'What is something you have never been able to be honest about with anyone?'),
  q('b1-089', 'deep', 'What is the kindest thing you have done that nobody knows about?'),
  q('b1-090', 'deep', 'What makes you feel genuinely chosen?'),
  q('b1-091', 'deep', 'What is a fear you have about us, even a small one?'),
  q('b1-092', 'deep', 'What do you think you are like to love?'),
  q('b1-093', 'deep', 'When did you last feel lonely, and what would have helped?'),
  q('b1-094', 'deep', 'What is something you have outgrown but still catch yourself doing?'),
  q('b1-095', 'deep', 'What do you want to be true about you in ten years that is not yet?'),
  q('b1-096', 'deep', 'What is the difference between how you seem and how you actually are?'),
  q('b1-097', 'deep', 'What is something you would want me to do if you went quiet for a while?'),
  q('b1-098', 'deep', 'What has been the loneliest period of your life, and what got you through?'),
  q('b1-099', 'deep', 'What do you think is the most misunderstood thing about you?'),
  q('b1-100', 'deep', 'What is something I do that makes you feel looked after?'),
  q('b1-101', 'deep', 'What would you like to be braver about?'),
  q('b1-102', 'deep', 'What is something you have never asked me but have wondered about?'),

  /* --------------------------------------------------------------- future */
  q('b1-103', 'future', 'What is the first thing you want to do when we are finally in the same place?'),
  q('b1-104', 'future', 'What does an ordinary Tuesday with me look like, in your head?'),
  q('b1-105', 'future', 'What is something you want us to be better at?'),
  q('b1-106', 'future', 'Where do you want to wake up on your fortieth birthday?'),
  q('b1-107', 'future', 'What is a tradition you want us to have that we do not have yet?'),
  q('b1-108', 'future', 'What kind of home do you want, not the house, the feeling of it?'),
  q('b1-109', 'future', 'What is something you want to learn, and would you want me learning it too?'),
  q('b1-110', 'future', 'What do you want more of in your life in six months?'),
  q('b1-111', 'future', 'What is a trip you want to take that has nothing to do with the destination?'),
  q('b1-112', 'future', 'What do you hope has not changed about us in ten years?'),
  q('b1-113', 'future', 'What is a goal of yours I could actually help with?'),
  q('b1-114', 'future', 'What does a good argument between us look like?'),
  q('b1-115', 'future', 'What is something you want to stop putting off?'),
  q('b1-116', 'future', 'How do you want to be looked after when you are ill or exhausted?'),
  q('b1-117', 'future', 'What is a version of your life you have quietly given up on, and should you have?'),
  q('b1-118', 'future', 'What would you want our first shared space to have in it?'),
  q('b1-119', 'future', 'What is something you want to do together that most couples would find boring?'),
  q('b1-120', 'future', 'What do you want to be known for?'),
  q('b1-121', 'future', 'What is a promise you would like us to make and actually keep?'),
  q('b1-122', 'future', 'What is something you want me to remind you of when you forget it?'),
  q('b1-123', 'future', 'What does supporting each other look like when one of us is failing at something?'),
  q('b1-124', 'future', 'What is a small thing you want to start doing every day?'),
  q('b1-125', 'future', 'What would you want a normal weekend with me to be like?'),
  q('b1-126', 'future', 'What do you want to have said yes to by this time next year?'),
  q('b1-127', 'future', 'What is something about the future that genuinely excites you?'),
  q('b1-128', 'future', 'What would make you feel most secure about where this is going?'),
  q('b1-129', 'future', 'What is a hard conversation we will need to have eventually?'),
  q('b1-130', 'future', 'What do you want your relationship with your work to look like?'),
  q('b1-131', 'future', 'What is something you would want us to do on a really bad day?'),
  q('b1-132', 'future', 'What would you want me to have learned about you a year from now?'),
  q('b1-133', 'future', 'What is a place you want to show me, and what will you show me first?'),
  q('b1-134', 'future', 'What kind of old person do you want to be?'),

  /* ---------------------------------------------------------------- apart */
  q('b1-135', 'apart', 'What is the hardest part of the day when we are apart?'),
  q('b1-136', 'apart', 'What do you miss that is not the obvious thing?'),
  q('b1-137', 'apart', 'What is something you wanted to show me today but could not?'),
  q('b1-138', 'apart', 'What does a good day apart look like, honestly?'),
  q('b1-139', 'apart', 'What do you do when you miss me and cannot say so right then?'),
  q('b1-140', 'apart', 'What is something about distance that has been unexpectedly good for us?'),
  q('b1-141', 'apart', 'When during the day do you think about me without meaning to?'),
  q('b1-142', 'apart', 'What would you want me to send you on a bad day, with no explanation?'),
  q('b1-143', 'apart', 'What is a small thing I could do from here that would actually help?'),
  q('b1-144', 'apart', 'What do you wish I could see about your day-to-day life?'),
  q('b1-145', 'apart', 'What is the worst thing about explaining us to other people?'),
  q('b1-146', 'apart', 'What do you find yourself saving up to tell me?'),
  q('b1-147', 'apart', 'What is something you have learned about yourself from being apart?'),
  q('b1-148', 'apart', 'What does your room look like right now, honestly, no tidying first?'),
  q('b1-149', 'apart', 'What is something ordinary about your day you have never described to me?'),
  q('b1-150', 'apart', 'When do you feel closest to me, despite everything?'),
  q('b1-151', 'apart', 'What do you worry I do not know about your life here?'),
  q('b1-152', 'apart', 'What is a sound or smell where you are that I would not recognise?'),
  q('b1-153', 'apart', 'What is the last thing you thought about before sleeping last night?'),
  q('b1-154', 'apart', 'What would you want to do together if we had exactly one hour, right now?'),
  q('b1-155', 'apart', 'What is something you have stopped telling me because it felt too small?'),
  q('b1-156', 'apart', 'Who in your life knows the most about me, and what have you told them?'),
  q('b1-157', 'apart', 'What is the thing you most want me to be there for?'),
  q('b1-158', 'apart', 'What do you do differently when you know we are about to talk?'),
  q('b1-159', 'apart', 'What is something you have wanted to ask me but keep not asking?'),
  q('b1-160', 'apart', 'What is a part of your day I would find boring but you would want me there for?'),
  q('b1-161', 'apart', 'What does missing someone feel like, physically, for you?'),
  q('b1-162', 'apart', 'What is something you are protecting me from knowing?'),
  q('b1-163', 'apart', 'What would you want me to notice about you that a screen does not show?'),
  q('b1-164', 'apart', 'What has this distance taught you that you would not have learned otherwise?'),
  q('b1-165', 'apart', 'What is the first thing you check when you wake up, and be honest.'),
  q('b1-166', 'apart', 'What is something you do that you would be embarrassed for me to walk in on?'),
  q('b1-167', 'apart', 'What do you wish we could do at the same time, from where we each are?'),
  q('b1-168', 'apart', 'What is a moment today you would have wanted me to see?'),
  q('b1-169', 'apart', 'What is the hardest thing about not being able to just show up?'),
  q('b1-170', 'apart', 'What would you want said to you tonight, in someone else’s words or mine?'),
  q('b1-171', 'apart', 'What is something you have been putting off telling me?'),
  q('b1-172', 'apart', 'What does home mean to you right now?'),
  q('b1-173', 'apart', 'What is a way I could make an ordinary Wednesday feel like something?'),
  q('b1-174', 'apart', 'What is the best thing anyone said to you this week?'),
  q('b1-175', 'apart', 'What do you need more of from me lately?'),
  q('b1-176', 'apart', 'What is something you would rather I asked you directly?'),
  q('b1-177', 'apart', 'What is a small ritual of ours that you would miss if it stopped?'),
  q('b1-178', 'apart', 'What is the kindest thing I have done from this far away?'),
  q('b1-179', 'apart', 'What do you want me to know before you go to sleep tonight?'),
  q('b1-180', 'apart', 'What has today actually been like, past the version you would normally give?'),
]);

/**
 * Every batch, oldest first. NEVER reorder or edit a shipped batch - see the
 * header. Append a new one.
 */
export const QUESTION_BATCHES = Object.freeze([
  Object.freeze({ id: 'b1', questions: BATCH_ONE }),
]);

/** Flat view, in batch order. The shuffle happens per batch, not across them. */
export const ALL_QUESTIONS = Object.freeze(
  QUESTION_BATCHES.flatMap((batch) => batch.questions)
);

/** @param {string} id @returns {{id: string, tone: string, text: string}|null} */
export function findQuestion(id) {
  return ALL_QUESTIONS.find((question) => question.id === id) || null;
}

export default { QUESTION_BATCHES, ALL_QUESTIONS, findQuestion };
