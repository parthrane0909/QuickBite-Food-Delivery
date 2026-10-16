"""Import every model so Base.metadata is complete for Alembic autogenerate."""

from app.db.models.checkout_idempotency import CheckoutIdempotency
from app.db.models.driver_assignment import DriverAssignment
from app.db.models.menu_item import MenuItem
from app.db.models.notification import Notification
from app.db.models.order import Order
from app.db.models.order_item import OrderItem
from app.db.models.order_status_history import OrderStatusHistory
from app.db.models.outbox_event import OutboxEvent
from app.db.models.processed_event import ProcessedEvent
from app.db.models.quarantine_record import QuarantineRecord
from app.db.models.restaurant import Restaurant
from app.db.models.retry_job import RetryJob
from app.db.models.simulated_payment import SimulatedPayment
from app.db.models.user import User

__all__ = [
    "CheckoutIdempotency",
    "DriverAssignment",
    "MenuItem",
    "Notification",
    "Order",
    "OrderItem",
    "OrderStatusHistory",
    "OutboxEvent",
    "ProcessedEvent",
    "QuarantineRecord",
    "Restaurant",
    "RetryJob",
    "SimulatedPayment",
    "User",
]
