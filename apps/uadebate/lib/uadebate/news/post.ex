defmodule Uadebate.News.Post do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uadebate.Text

  @rubrics ~w(announcements results interviews tips community)

  schema "news_posts" do
    field :title, :string
    field :slug, :string
    field :rubric, :string, default: "community"
    field :summary, :string
    field :body, :string, default: ""
    # nil while the post is a draft
    field :published_at, :utc_datetime
    # cab account ids, read downward; never a foreign key into cab
    field :author_user_id, :integer
    field :editor_user_id, :integer
    # a file name in Uadebate.Uploads; nil shows the gradient
    field :image, :string
    field :image_alt, :string
    # private labels, loaded only under /manage
    many_to_many :tags, Uadebate.Tags.Tag,
      join_through: "news_tags",
      join_keys: [post_id: :id, tag_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def rubrics, do: @rubrics

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :slug, :rubric, :summary, :body, :image_alt])
    |> Text.clean_text(:title, required: true, max: 200)
    |> Text.clean_text(:slug, max: 200)
    |> Text.clean_text(:image_alt, max: 200)
    |> Text.clean_text(:summary, max: 1000, multiline: true)
    |> Text.clean_text(:body, max: 20_000, multiline: true, blank: "")
    |> update_change(:slug, &slugify/1)
    |> put_slug()
    |> validate_required([:title, :slug, :rubric])
    |> validate_inclusion(:rubric, @rubrics)
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/)
    |> unique_constraint(:slug)
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      blank when blank in [nil, ""] -> put_change(changeset, :slug, slugify(get_field(changeset, :title)))
      _ -> changeset
    end
  end

  @doc "A URL slug from free text: lowercase ASCII words joined by dashes."
  def slugify(nil), do: nil

  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
