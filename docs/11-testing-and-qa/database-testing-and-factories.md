# Database Testing & FactoryBoy Data Generation

Manually constructing test entities (`user = User.objects.create(name="a", email="b@b.com", ... 15 required fields)`) produces brittle, unreadable test suites. When you add a new required column, hundreds of tests break.

The industry-standard solution is **FactoryBoy**: a fixture replacement tool that uses Faker to generate realistic, dynamic model instances.

---

## 1. Defining Model Factories with FactoryBoy

=== "Django REST Framework (FactoryBoy)"
    ```python
    # tests/factories.py
    import factory
    from factory.django import DjangoModelFactory
    from decimal import Decimal
    from myapp.models import User, Product, Order, OrderItem

    class UserFactory(DjangoModelFactory):
        class Meta:
            model = User

        username = factory.Faker("user_name")
        email = factory.Faker("email")
        is_active = True

    class ProductFactory(DjangoModelFactory):
        class Meta:
            model = Product

        name = factory.Faker("catch_phrase")
        price = factory.LazyFunction(lambda: Decimal("49.99"))
        stock_quantity = 100

    class OrderFactory(DjangoModelFactory):
        class Meta:
            model = Order

        # Automatically generates and links a user!
        user = factory.SubFactory(UserFactory)
        status = Order.Status.PENDING
        total_amount = Decimal("0.00")
    ```

    ```python
    # tests/test_orders.py
    import pytest
    from tests.factories import UserFactory, ProductFactory, OrderFactory

    @pytest.mark.django_db
    def test_order_creation_with_factory():
        # Creates a complete, valid user and product with zero boilerplate!
        product = ProductFactory(stock_quantity=50, price=20.0)
        order = OrderFactory()
        
        assert order.user.email is not None
        assert product.stock_quantity == 50
    ```

=== "FastAPI / SQLAlchemy 2.0 (SQLAlchemyModelFactory)"
    ```python
    # tests/factories_sqlalchemy.py
    import factory
    from app.models.user import User

    class SQLAlchemyUserFactory(factory.alchemy.SQLAlchemyModelFactory):
        class Meta:
            model = User
            sqlalchemy_session_persistence = "commit"

        email = factory.Faker("email")
        hashed_password = "fake_test_hash"
        is_active = True
    ```

---

## 2. Database Isolation: Transaction Rollbacks

A critical requirement of backend tests is **Isolation**: Test A must never see data created by Test B.

Instead of running slow `TRUNCATE TABLE` or `flush` commands between tests, **wrap each test in an atomic database transaction and issue a `ROLLBACK` when the test completes**.

This runs in sub-milliseconds, allowing test suites with 500+ database tests to finish in seconds.

