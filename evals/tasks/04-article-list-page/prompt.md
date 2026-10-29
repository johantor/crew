Add an article list page type. It lists its child articles ten per page, newest first, with
links to the previous and next page (`?page=2`).

Put the paging in `ArticleService` as
`IReadOnlyList<ArticlePage> GetPage(ContentReference parent, int page, int pageSize)`: the
articles on that page (pages count from 1), under the same rules as `GetLatest`. Cover it with
tests.
