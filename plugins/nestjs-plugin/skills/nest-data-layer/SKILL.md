---
name: nest-data-layer
description: |
  ORM patterns for NestJS: TypeORM, Prisma, Mongoose. Covers entities, repositories, transactions, migrations, common pitfalls (N+1, cascade deletes, transaction boundaries).

  Use this skill to:
  - Detect which ORM the project uses and apply matching patterns.
  - Define entities/schemas with the right decorators.
  - Inject repositories or Prisma client correctly.
  - Run transactions at the service boundary.
  - Write migrations that round-trip cleanly.

  Do NOT use this skill for:
  - Module/DI patterns (see nest-conventions).
  - Decorator usage broadly (see decorator-patterns).
  - Non-ORM raw SQL (rare; flag in BLOCKERS if needed).
user-invocable: false
paths: ["src/**/*.ts"]
---

# NestJS Data Layer

This skill consolidates ORM patterns for the three most common choices in NestJS projects: TypeORM, Prisma, Mongoose. Detect which is in use, then apply the matching section.

## Detection

| Marker (in `dependencies`) | ORM |
|---|---|
| `@nestjs/typeorm` + `typeorm` | TypeORM |
| `@prisma/client` + `prisma` | Prisma |
| `@nestjs/mongoose` + `mongoose` | Mongoose |
| (multiple) | Hybrid project — match each feature's existing pattern |
| (none) | Raw driver (`pg`, `mysql2`) — flag in DECISIONS |

## TypeORM

### Module setup

```ts
// src/app.module.ts
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        url: config.get<string>('DATABASE_URL'),
        autoLoadEntities: true,
        synchronize: false,                 // NEVER true in prod — use migrations
        migrations: ['dist/migrations/*.js'],
        migrationsRun: false,
        logging: config.get<string>('NODE_ENV') !== 'production',
      }),
    }),
  ],
})
```

### Entity

```ts
// src/users/entities/user.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, Index, OneToMany } from 'typeorm';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index({ unique: true })
  @Column({ length: 255 })
  email!: string;

  @Column({ select: false })            // hash never selected by default
  passwordHash!: string;

  @Column({ type: 'jsonb', default: {} })
  metadata!: Record<string, unknown>;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;

  @OneToMany(() => Order, (order) => order.user)
  orders!: Order[];
}
```

- `select: false` for sensitive columns (passwords, tokens) — must explicitly `.addSelect('user.passwordHash')`.
- `@Index({ unique: true })` instead of `@Column({ unique: true })` for clarity at index level.
- Use `relations` array on find options (not eager: true) — eager loading is hard to opt out of later.

### Repository injection

```ts
// src/users/users.module.ts
@Module({
  imports: [TypeOrmModule.forFeature([User])],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}

// src/users/users.service.ts
@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
  ) {}

  async findByEmail(email: string): Promise<User | null> {
    return this.users.findOne({ where: { email } });
  }
}
```

### Query builder for complex queries

```ts
async findActiveAdmins(after: Date) {
  return this.users
    .createQueryBuilder('user')
    .innerJoin('user.roles', 'role')
    .where('role.name = :name', { name: 'admin' })
    .andWhere('user.lastLoginAt > :after', { after })
    .orderBy('user.email', 'ASC')
    .limit(100)
    .getMany();
}
```

Always parameterize (`:name`, `:after`) — never string-concat user input.

### Transactions

Use `EntityManager.transaction` or `DataSource.transaction`:

```ts
@Injectable()
export class OrdersService {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  async placeOrder(userId: string, items: OrderItem[]): Promise<Order> {
    return this.dataSource.transaction(async (manager) => {
      const order = manager.create(Order, { userId, status: 'pending' });
      await manager.save(order);
      for (const item of items) {
        await manager.save(manager.create(OrderItem, { ...item, orderId: order.id }));
      }
      await manager.update(User, userId, { lastOrderAt: new Date() });
      return order;
    });
  }
}
```

Pass `manager` explicitly down — never reach for the global repository inside a transaction.

### Migrations

```bash
# generate from current entity diff
npx typeorm-ts-node-commonjs migration:generate -d src/data-source.ts src/migrations/AddUserMetadata

# run pending
npx typeorm-ts-node-commonjs migration:run -d src/data-source.ts

# revert last
npx typeorm-ts-node-commonjs migration:revert -d src/data-source.ts
```

Each migration is timestamped — never edit after merge. Write a follow-up.

### Common pitfalls

- **N+1**: `users.find({ relations: ['orders'] })` runs ONE query with JOIN. `users.find()` then `.orders` accessed in a loop runs N queries. Always declare `relations` upfront.
- **`save` vs `insert`**: `save` does INSERT or UPDATE based on PK presence — silent. `insert` always inserts; `update` always updates. Use the explicit method.
- **`synchronize: true` in prod** — drops/recreates schema on entity change. Catastrophic.
- **Cascading deletes** — `@OneToMany({ cascade: ['remove'] })` only cascades through TypeORM, not at DB level. Combine with `onDelete: 'CASCADE'` on the FK side.
- **Lazy relations** — `Promise<User>` on a property looks neat but causes implicit queries. Avoid.

## Prisma

### Service setup

```ts
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  async onModuleInit() {
    await this.$connect();
  }
}

// src/prisma/prisma.module.ts
@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

### Schema (`prisma/schema.prisma`)

```prisma
generator client { provider = "prisma-client-js" }
datasource db { provider = "postgresql"; url = env("DATABASE_URL") }

model User {
  id           String   @id @default(uuid())
  email        String   @unique
  passwordHash String
  metadata     Json     @default("{}")
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
  orders       Order[]

  @@index([email])
  @@map("users")
}
```

### Service usage

```ts
@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  findByEmail(email: string) {
    return this.prisma.user.findUnique({ where: { email } });
  }

  create(input: Prisma.UserCreateInput) {
    return this.prisma.user.create({ data: input });
  }
}
```

Prisma's generated types (`Prisma.UserCreateInput`, `User`) are first-class. Use them in DTOs:

```ts
type CreateUserPayload = Pick<Prisma.UserCreateInput, 'email' | 'passwordHash'>;
```

### Transactions

```ts
async transfer(fromId: string, toId: string, amount: number) {
  return this.prisma.$transaction(async (tx) => {
    await tx.account.update({ where: { id: fromId }, data: { balance: { decrement: amount } } });
    await tx.account.update({ where: { id: toId }, data: { balance: { increment: amount } } });
  });
}
```

For interactive transactions across services, pass `tx` down. Avoid `$transaction([op1, op2])` array form when you need conditional logic — use the callback form.

### Migrations

```bash
npx prisma migrate dev --name add_user_metadata    # dev: generate + apply
npx prisma migrate deploy                           # prod: apply only
npx prisma generate                                 # regenerate client after schema change
```

`prisma migrate dev` rewrites history if you change a migration before merging — fine in dev. After merge, only `migrate deploy` (apply forward).

### Common pitfalls

- **Forgetting `prisma generate`** after schema change — TS types stale, runtime breaks.
- **`$queryRawUnsafe` with user input** — string interpolation = SQL injection. Use `$queryRaw` with template literal.
- **Missing `@unique` on lookup field** — `findUnique` requires a unique constraint; otherwise use `findFirst`.
- **`upsert` race conditions** — read-then-write inside a transaction or use unique constraint.
- **Enabling `previewFeatures` casually** — they break between Prisma versions.

## Mongoose

### Module setup

```ts
@Module({
  imports: [
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        uri: config.get<string>('MONGO_URL'),
      }),
    }),
  ],
})
```

### Schema

```ts
// src/users/schemas/user.schema.ts
import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true, index: true })
  email!: string;

  @Prop({ required: true, select: false })
  passwordHash!: string;

  @Prop({ type: Object, default: {} })
  metadata!: Record<string, unknown>;
}

export const UserSchema = SchemaFactory.createForClass(User);
```

### Model injection

```ts
// src/users/users.module.ts
@Module({
  imports: [MongooseModule.forFeature([{ name: User.name, schema: UserSchema }])],
  providers: [UsersService],
})

// src/users/users.service.ts
@Injectable()
export class UsersService {
  constructor(@InjectModel(User.name) private readonly userModel: Model<UserDocument>) {}

  findByEmail(email: string) {
    return this.userModel.findOne({ email }).exec();
  }
}
```

Always `.exec()` for true Promise (otherwise it's a Mongoose Query — works in await but error stacks suffer).

### Transactions (replica sets)

```ts
async transfer(fromId: string, toId: string, amount: number) {
  const session = await this.connection.startSession();
  try {
    session.startTransaction();
    await this.accountModel.updateOne({ _id: fromId }, { $inc: { balance: -amount } }, { session });
    await this.accountModel.updateOne({ _id: toId }, { $inc: { balance: +amount } }, { session });
    await session.commitTransaction();
  } catch (err) {
    await session.abortTransaction();
    throw err;
  } finally {
    session.endSession();
  }
}
```

Requires Mongo replica set (single-node cluster acceptable for dev with `--replSet`).

### Common pitfalls

- **No `.exec()`** on queries — debugging stacks point inside Mongoose internals.
- **Sub-document `_id`** auto-generation — turn off with `_id: false` if you don't need it.
- **`save()` vs `updateOne()`** — `save()` runs validators and middleware; `updateOne()` doesn't (unless `runValidators: true`).
- **`findOneAndUpdate` returns OLD doc by default** — pass `{ new: true }` for the updated version.
- **Transactions on standalone Mongo** — silently no-op. Check the deployment.

## Choosing between ORMs (when starting fresh)

This is BA territory, not nest-architect's call. But for context:

- **TypeORM** — class-based entities; familiar to Java/C# devs; integrates well with NestJS DI; query builder. Schema-first feel.
- **Prisma** — schema-first DSL; generated types; best DX for migrations and tooling. Less Active-Record, more Data-Mapper-ish.
- **Mongoose** — only if Mongo is the answer. Avoid for relational data.

## Anti-patterns (all ORMs)

- ❌ ORM operations from controllers (always go through services).
- ❌ Editing migrations after merge.
- ❌ `synchronize: true` / `--accept-data-loss` in prod scripts.
- ❌ String concatenation in queries (`'WHERE id = ' + userId`).
- ❌ Cascade-deleting through ORM only (without DB FK constraints) — partial deletes leave orphans on direct DB access.
- ❌ Loading entire collections without pagination (`findAll` with no `take`/`skip`).
- ❌ N+1 by accessing relations in loops without eager loading.
- ❌ Mixing transactional and non-transactional repositories in one operation.
