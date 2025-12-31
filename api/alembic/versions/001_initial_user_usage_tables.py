"""initial user and usage_log tables

Revision ID: 001
Revises:
Create Date: 2025-12-31

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("email", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("entitlement", sa.String(), nullable=False, server_default="free"),
        sa.Column("apple_user_id", sa.String(), nullable=True),
        sa.Column("last_login_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email"),
        sa.UniqueConstraint("apple_user_id"),
    )
    op.create_index(op.f("ix_user_email"), "user", ["email"], unique=True)

    op.create_table(
        "usage_log",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("endpoint", sa.String(), nullable=False),
        sa.Column("watch_id", sa.String(), nullable=True),
        sa.Column("tokens_used", sa.Integer(), nullable=False),
        sa.Column("provider", sa.String(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_usage_log_user_id"), "usage_log", ["user_id"], unique=False)
    op.create_index(op.f("ix_usage_log_created_at"), "usage_log", ["created_at"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_usage_log_created_at"), table_name="usage_log")
    op.drop_index(op.f("ix_usage_log_user_id"), table_name="usage_log")
    op.drop_table("usage_log")
    op.drop_index(op.f("ix_user_email"), table_name="user")
    op.drop_table("user")
