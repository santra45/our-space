import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const mobile = join(here, '..');

const bank = await import(pathToFileURL(join(repo, 'src', 'data', 'dailyQuestions.js')).href);

function literal(source, name) {
  const match = new RegExp(`const ${name} = (\\[[\\s\\S]*?\\n\\]);`).exec(source);
  if (!match) throw new Error(`could not find ${name}`);
  return Function(`"use strict"; return (${match[1]});`)();
}

const roulette = readFileSync(join(repo, 'src', 'components', 'scratchoff', 'DateRoulette.jsx'), 'utf8');
const bucket = readFileSync(join(repo, 'src', 'components', 'bucketlist', 'BucketList.jsx'), 'utf8');

const ideas = literal(roulette, 'DEFAULT_IDEAS');
const bucketItems = literal(bucket, 'DEFAULT_BUCKET_ITEMS');

const categoriesBlock = /const CATEGORIES = \[([\s\S]*?)\n\];/.exec(roulette);
if (!categoriesBlock) throw new Error('could not find CATEGORIES');
const categories = [...categoriesBlock[1].matchAll(/\{ id: '([^']+)', label: '([^']+)'/g)].map((m) => ({
  id: m[1],
  label: m[2],
}));

const bucketOptions = [];
const seenOptions = new Set();
for (const m of bucket.matchAll(/<option value="([^"]+)">([^<]+)<\/option>/g)) {
  if (seenOptions.has(m[1])) continue;
  seenOptions.add(m[1]);
  bucketOptions.push({ value: m[1], label: m[2] });
}

const roulettePrompt = /ROULETTE_STATE_ID = '([^']+)'/.exec(roulette)[1];

function dart(value) {
  return `'${String(value)
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\$/g, '\\$')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')}'`;
}

const lines = [];
lines.push("import '../../../models/daily_answers_record.dart';");
lines.push("import '../../../models/date_idea_record.dart';");
lines.push('');
lines.push(`const String rouletteStateId = ${dart(roulettePrompt)};`);
lines.push('');
lines.push('const List<QuestionBatch> questionBatches = [');
for (const batch of bank.QUESTION_BATCHES) {
  lines.push(`  QuestionBatch(id: ${dart(batch.id)}, questions: [`);
  for (const q of batch.questions) {
    lines.push(`    DailyQuestion(id: ${dart(q.id)}, tone: ${dart(q.tone)}, text: ${dart(q.text)}),`);
  }
  lines.push('  ]),');
}
lines.push('];');
lines.push('');
lines.push('const List<DateIdea> defaultDateIdeas = [');
for (const idea of ideas) {
  lines.push(
    `  DateIdea(id: ${dart(idea.id)}, title: ${dart(idea.title)}, category: ${dart(idea.category)}, desc: ${dart(idea.desc)}),`
  );
}
lines.push('];');
lines.push('');
lines.push('const List<DateIdeaCategory> dateIdeaCategories = [');
for (const c of categories) {
  lines.push(`  DateIdeaCategory(id: ${dart(c.id)}, label: ${dart(c.label)}),`);
}
lines.push('];');
lines.push('');
lines.push('class DefaultBucketItem {');
lines.push('  const DefaultBucketItem({required this.text, required this.category});');
lines.push('');
lines.push('  final String text;');
lines.push('  final String category;');
lines.push('}');
lines.push('');
lines.push('const List<DefaultBucketItem> defaultBucketItems = [');
for (const item of bucketItems) {
  lines.push(`  DefaultBucketItem(text: ${dart(item.text)}, category: ${dart(item.category)}),`);
}
lines.push('];');
lines.push('');
lines.push('class BucketCategoryOption {');
lines.push('  const BucketCategoryOption({required this.value, required this.label});');
lines.push('');
lines.push('  final String value;');
lines.push('  final String label;');
lines.push('}');
lines.push('');
lines.push('const List<BucketCategoryOption> bucketCategoryOptions = [');
for (const option of bucketOptions) {
  lines.push(`  BucketCategoryOption(value: ${dart(option.value)}, label: ${dart(option.label)}),`);
}
lines.push('];');
lines.push('');

const target = join(mobile, 'lib', 'core', 'engine', 'data', 'web_data.dart');
writeFileSync(target, lines.join('\n'));
console.log(
  `wrote ${target}: ${bank.ALL_QUESTIONS.length} questions, ${ideas.length} ideas, ${categories.length} categories, ${bucketItems.length} bucket items, ${bucketOptions.length} bucket options`
);
