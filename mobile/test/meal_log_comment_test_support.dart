import 'package:smart_nutrition_mobile/features/nutrition/meal_log_comment_api.dart';
import 'meal_log_test_support.dart';

const rootCommentId = '88888888-8888-4888-8888-888888888888';
const commentAuthorId = '77777777-7777-4777-8777-777777777777';
MealLogComment rootComment({
  String id = rootCommentId,
  String meal = mealId,
  String text = 'Sentetik diyetisyen yorumu',
}) => MealLogComment(
  id: id,
  mealLogId: meal,
  authorUserId: commentAuthorId,
  text: text,
  createdAt: DateTime.utc(2026, 11, 18, 12),
  parentCommentId: null,
);
MealLogComment clientReply({
  String author = '44444444-4444-4444-8444-444444444444',
  String text = 'Sentetik danışan yanıtı',
}) => MealLogComment(
  id: '99999999-9999-4999-8999-999999999999',
  mealLogId: mealId,
  authorUserId: author,
  text: text,
  createdAt: DateTime.utc(2026, 11, 18, 12, 1),
  parentCommentId: rootCommentId,
);
Map<String, Object?> commentJson(MealLogComment row) => {
  'id': row.id,
  'mealLogId': row.mealLogId,
  'authorUserId': row.authorUserId,
  'text': row.text,
  'createdAt': row.createdAt.toIso8601String(),
  'parentCommentId': row.parentCommentId,
};

class CommentTestApi extends MealLogCommentApi {
  CommentTestApi(super.session);
  List<MealLogComment> rows = [rootComment()];
  final pages = <int>[];
  int writes = 0;
  String? lastParent, lastText;
  MealLogCommentApiException? readFailure, writeFailure;
  Future<MealLogCommentPage>? pendingRead;
  Future<MealLogComment>? pendingWrite;
  @override
  Future<MealLogCommentPage> list(String mealLogId, {int page = 1}) async {
    pages.add(page);
    if (readFailure != null) {
      throw readFailure!;
    }
    return pendingRead ??
        (
          items: rows.skip((page - 1) * 10).take(10).toList(),
          totalCount: rows.length,
        );
  }

  @override
  Future<MealLogComment> reply(
    String mealLogId,
    MealLogComment parent,
    String text,
  ) async {
    writes++;
    lastParent = parent.id;
    lastText = text.trim();
    if (writeFailure != null) {
      throw writeFailure!;
    }
    final previousRows = rows;
    final result =
        await (pendingWrite ??
            Future.value(
              clientReply(author: session.user!.id, text: text.trim()),
            ));
    previousRows.add(result);
    return result;
  }
}
