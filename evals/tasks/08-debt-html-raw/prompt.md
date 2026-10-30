Debt: the article view renders `MainBody` through `Html.Raw`, which skips on-page editing and
the CMS's own rendering of the rich text. Fix it.
