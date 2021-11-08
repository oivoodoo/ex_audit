defmodule AssocTest do
  use ExUnit.Case

  import Ecto.Query

  alias ExAudit.Test.{Repo, Version, BlogPost, Comment, Util, User, UserGroup}
  alias ExAudit.Test.BlogPost.Section

  test "comment lifecycle tracked" do
    user = Util.create_user()

    ExAudit.track(actor_id: user.id)

    params = %{
      title: "Controversial post",
      author_id: user.id,
      comments: [
        %{
          body: "lorem impusdrfnia",
          author_id: user.id
        }
      ]
    }

    changeset = BlogPost.changeset(%BlogPost{}, params)
    {:ok, %{comments: [comment]}} = Repo.insert(changeset)

    [%{actor_id: actor_id}] = comment_history = Repo.history(comment)
    assert length(comment_history) == 1
    assert actor_id == user.id
  end

  test "structs configured as primitives are treated as primitives" do
    {:ok, old_date} = Date.new(2000, 1, 1)
    params = %{name: "Bob", email: "foo@bar.com", birthday: old_date}
    changeset = User.changeset(%User{}, params)
    {:ok, user} = Repo.insert(changeset)

    new_date = Date.add(old_date, 17)
    params = %{birthday: new_date}
    changeset = User.changeset(user, params)
    {:ok, user} = Repo.update(changeset)

    [version | _] = Repo.history(user)

    assert %{
             patch: %{
               birthday: {:changed, {:primitive_change, ^old_date, ^new_date}}
             }
           } = version
  end

  test "should track cascading deletions (before they happen)" do
    user = Util.create_user()

    ExAudit.track(actor_id: user.id)

    params = %{
      title: "Controversial post",
      author_id: user.id,
      comments: [
        %{
          body: "lorem impusdrfnia",
          author_id: user.id
        },
        %{
          body: "That's a nice article",
          author_id: user.id
        },
        %{
          body: "We want more of this CONTENT",
          author_id: user.id
        }
      ]
    }

    changeset = BlogPost.changeset(%BlogPost{}, params)
    {:ok, %{comments: comments} = blog_post} = Repo.insert(changeset)

    Repo.delete(blog_post)

    comment_ids = Enum.map(comments, & &1.id)

    versions =
      Repo.all(
        from(v in Version,
          where: v.entity_id in ^comment_ids,
          where: v.entity_schema == ^Comment
        )
      )

    # 3 created, 3 deleted
    assert length(versions) == 6
  end

  test "should track properly embded assoc" do
    params = %{title: "Welcome!"}

    changeset = BlogPost.changeset(%BlogPost{}, params)
    {:ok, blog_post} = Repo.insert(changeset)
    assert Repo.history(blog_post) |> Enum.count() == 1

    changeset =
      BlogPost.changeset(blog_post, %{
        sections: [
          %{title: "title 1", text: "text 1"}
        ]
      })
    {:ok, blog_post} = Repo.update(changeset)
    assert Repo.history(blog_post) |> Enum.count() == 2

    changeset =
      BlogPost.changeset(blog_post, %{
        title: "title 2"
      })
    {:ok, blog_post} = Repo.update(changeset)
    assert Repo.history(blog_post) |> Enum.count() == 3

    [version1, version2, version3] = Repo.history(blog_post)
    assert Repo.get!(BlogPost, blog_post.id).title == "title 2"
    Repo.revert(version1)
    assert Repo.history(blog_post) |> Enum.count() == 4
    assert Repo.get!(BlogPost, blog_post.id).title == "Welcome!"

    changeset =
      BlogPost.changeset(blog_post, %{
        sections: []
      })
    {:ok, blog_post} = Repo.update(changeset)
    assert Repo.history(blog_post) |> Enum.count() == 5
    assert Repo.get!(BlogPost, blog_post.id).sections == []

    [version1, version2, version3, version4, version5] = Repo.history(blog_post)
    Repo.revert(version2)
    assert Repo.history(blog_post) |> Enum.count() == 6

    [section1] = Repo.get!(BlogPost, blog_post.id).sections
    assert section1.title == "title 1"
    assert section1.text == "text 1"
  end

  test "should return changesets from constraint errors" do
    user = Util.create_user()

    ch = UserGroup.changeset(%UserGroup{}, %{name: "a group", user_id: user.id})
    {:ok, _group} = Repo.insert(ch)

    import Ecto.Changeset

    deletion =
      user
      |> change
      |> no_assoc_constraint(:groups)

    assert {:error, %Ecto.Changeset{}} = Repo.delete(deletion)
  end
end
